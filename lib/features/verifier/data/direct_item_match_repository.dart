import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_ai/firebase_ai.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';
import 'item_match_catalog.dart';
import 'item_match_model.dart';
import 'item_match_prompt.dart';
import 'item_match_repository.dart';

/// Matches by calling Gemini directly from the device through Firebase AI Logic.
///
/// The route is phone -> Google -> phone. The path it replaces was phone ->
/// Cloudflare -> Supabase -> Google -> Supabase -> Cloudflare -> phone, where a
/// no-op call to the edge function alone measured ~320 ms warm and up to 2.2 s
/// cold, before any work happened at all. That turned out to be the small term:
/// a device run on 2026-08-24 took roughly a minute on the direct route too, so
/// the wait lives in generation, not in routing.
///
/// The catalog comes from inventory the screen already holds, loaded under RLS,
/// so the model only ever sees rows this user can already see and no separate
/// fetch is needed. Ids are never sent -- see [ItemMatchCatalog] -- and refs the
/// model invents resolve to nothing, so nothing it makes up can reach an order.
class DirectItemMatchRepository implements ItemMatchRepository {
  final ItemMatchModel _model;

  /// Test seam. The real timings are the constants below, but a test proving
  /// that a slow call is not retried cannot afford to wait a minute to do it.
  final Duration? _idleTimeoutOverride;
  final Duration? _ceilingOverride;

  DirectItemMatchRepository({
    ItemMatchModel? model,
    Duration? idleTimeout,
    Duration? ceiling,
  })  : _model = model ?? FirebaseItemMatchModel(),
        _idleTimeoutOverride = idleTimeout,
        _ceilingOverride = ceiling;

  /// How long the model may say nothing at all before we treat it as stuck.
  ///
  /// This is the guard that matters, and it is deliberately loose. The previous
  /// version capped *total* elapsed time at 20 s against a call that answered in
  /// about 60 -- so the cap was not protecting anyone from a failure, it was
  /// manufacturing one, and the answer that did arrive was thrown away five
  /// seconds after the verifier had already been told the service was busy.
  /// Thinking happens before the first token, so early silence is normal work
  /// rather than a symptom. These are first-measurement numbers, set above the
  /// only real datapoint there is; the first-token timing logged in [_collect]
  /// is what will let them be tightened honestly.
  static const textIdleTimeout = Duration(seconds: 60);

  /// A backstop for a stream that keeps trickling and never ends. Someone is
  /// standing there holding a phone, so it is not generous -- but it is well
  /// past anything a working call has taken.
  static const textCeiling = Duration(seconds: 90);

  static const maxAttempts = 3;

  /// Prefixes every log line from this repository.
  static const _label = 'matchText';

  static const _backoffBase = Duration(milliseconds: 700);

  @override
  Future<AppResult<ItemMatchResult>> matchText(
    String text,
    List<InventoryItem> inventory,
  ) {
    logger.d('DirectItemMatchRepository → matchText: ${text.length} chars');
    return _match(text, inventory);
  }

  /// Nothing to wake: there is no function in front of Gemini any more, and
  /// spending a real generate call to warm a TLS connection would cost tokens
  /// to save milliseconds. Kept because the entry screens call it, and because
  /// switching back to the edge implementation should not need a UI change.
  @override
  Future<void> warmUp() async {}

  Future<AppResult<ItemMatchResult>> _match(
    String text,
    List<InventoryItem> inventory,
  ) async {
    if (inventory.isEmpty) {
      logger.w('DirectItemMatchRepository → $_label with an empty inventory');
      return const AppSuccess(ItemMatchResult(matches: [], unmatched: []));
    }

    final idleTimeout = _idleTimeoutOverride ?? textIdleTimeout;
    final ceiling = _ceilingOverride ?? textCeiling;
    final catalog = ItemMatchCatalog.of(inventory);
    final overallStart = DateTime.now();
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final started = DateTime.now();
      try {
        final (json, usage) = await _collect(
          attempt: attempt,
          started: started,
          catalog: catalog,
          idleTimeout: idleTimeout,
          ceiling: ceiling,
          text: text,
        );

        final result = _toResult(json, catalog);
        logger.i(
          'DirectItemMatchRepository → $_label ${result.matches.length} matches, '
          '${result.unmatched.length} unmatched, ${result.ambiguous.length} ambiguous '
          'in ${DateTime.now().difference(started).inMilliseconds}ms '
          '(attempt $attempt, ${usage?.summary ?? 'usage unreported'})',
        );
        return AppSuccess(result);
      } on TimeoutException catch (e) {
        // Deliberately NOT retried. A retry cannot cancel the attempt it is
        // replacing, so a second call does not take over from a slow one -- it
        // runs alongside it, competing for the same connection and billed in
        // full. Three of those is how one slow request turned into a hard
        // failure. A warning rather than an error, too: a slow link or a slow
        // model is not a crash and Crashlytics should not carry it as one.
        logger.w('DirectItemMatchRepository → $_label gave up waiting: $e');
        return const AppFailure(
          AppError(
            message: 'الاستجابة تأخرت أكثر من المعتاد، يرجى المحاولة مجدداً',
            type: AppErrorType.server,
          ),
        );
      } catch (e, st) {
        lastError = e;
        if (!_worthRetrying(e)) {
          logger.e('DirectItemMatchRepository → $_label failed', error: e, stackTrace: st);
          return AppFailure(_toAppError(e));
        }
        logger.w('DirectItemMatchRepository → $_label attempt $attempt failed: $e');
        if (attempt == maxAttempts) break;

        // Exponential, with jitter so a capacity spike doesn't turn every
        // waiting client into a synchronised second wave.
        final backoff = _backoffBase * pow(2, attempt - 1).toDouble() +
            Duration(milliseconds: Random().nextInt(250));
        if (DateTime.now().difference(overallStart) + backoff > ceiling) break;
        await Future<void>.delayed(backoff);
      }
    }

    logger.w('DirectItemMatchRepository → $_label exhausted: $lastError');
    return const AppFailure(
      AppError(
        message: 'الخدمة مزدحمة حالياً، يرجى المحاولة بعد لحظات',
        type: AppErrorType.server,
      ),
    );
  }

  /// Reads the streamed answer into one string.
  ///
  /// Two guards, measuring different things. [Stream.timeout] restarts on every
  /// chunk, so it fires only on real silence; [ceiling] catches a stream that
  /// trickles forever. Both leave the `await for` by throwing, which cancels the
  /// subscription -- and cancelling is the whole reason this is a stream rather
  /// than a future, because it is the one thing `Future.timeout` cannot do.
  Future<(String, ItemMatchUsage?)> _collect({
    required int attempt,
    required DateTime started,
    required ItemMatchCatalog catalog,
    required Duration idleTimeout,
    required Duration ceiling,
    required String text,
  }) async {
    final buffer = StringBuffer();
    final deadline = started.add(ceiling);
    ItemMatchUsage? usage;
    var sawFirstChunk = false;

    final chunks = _model
        .generate(
          systemInstruction: ItemMatchPrompt.textInstruction,
          catalogBlock: catalog.block,
          text: text,
        )
        .timeout(idleTimeout);

    await for (final chunk in chunks) {
      if (!sawFirstChunk && chunk.text.isNotEmpty) {
        sawFirstChunk = true;
        // The number that says where the minute actually goes: a long wait here
        // is thinking or the network, a long tail after it is generation.
        logger.d(
          'DirectItemMatchRepository → $_label first token after '
          '${DateTime.now().difference(started).inMilliseconds}ms (attempt $attempt)',
        );
      }
      buffer.write(chunk.text);
      usage = chunk.usage ?? usage;

      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          '$_label passed its ${ceiling.inSeconds}s ceiling still streaming',
          ceiling,
        );
      }
    }

    if (buffer.isEmpty) {
      throw const FormatException('The model returned no content');
    }
    return (buffer.toString(), usage);
  }

  /// Worth asking again only when the server answered with something a second
  /// ask can fix: a capacity blip, or malformed JSON. A bad key, a disabled API
  /// or an exhausted quota will fail identically however many times you ask.
  ///
  /// A timeout is handled before this and never reaches it -- see [_match].
  static bool _worthRetrying(Object error) {
    if (error is InvalidApiKey ||
        error is ServiceApiNotEnabled ||
        error is UnsupportedUserLocation ||
        // A 429 is a limit, not a hiccup. Asking again 700 ms later cannot
        // clear it, and it spends another request against the very quota that
        // just refused you -- so retrying here is a cost multiplier wearing the
        // costume of a rescue. This line was inherited from the edge function's
        // "retry on 429" rule, where it was equally wrong.
        error is QuotaExceeded) {
      return false;
    }
    if (error is ServerException) return true;
    // A FormatException means the model answered with something that isn't the
    // JSON it was asked for -- a re-roll genuinely can fix that.
    if (error is FormatException) return true;
    return error is! FirebaseAIException;
  }

  static AppError _toAppError(Object error) {
    if (error is QuotaExceeded) {
      // Distinct from the busy message on purpose: "try again in a moment" is
      // false here and, worse, acts on it. Nobody in the warehouse can clear a
      // quota, so the message points at the only person who can.
      return const AppError(
        message: 'تم استنفاد حصة خدمة الذكاء الاصطناعي، يرجى مراجعة الدعم الفني',
        type: AppErrorType.server,
      );
    }
    if (error is ServiceApiNotEnabled) {
      return const AppError(
        message: 'خدمة الذكاء الاصطناعي غير مفعّلة، يرجى مراجعة الدعم الفني',
        type: AppErrorType.server,
      );
    }
    if (error is InvalidApiKey || error is UnsupportedUserLocation) {
      return const AppError(
        message: 'تعذر الوصول إلى خدمة الذكاء الاصطناعي، يرجى مراجعة الدعم الفني',
        type: AppErrorType.server,
      );
    }
    return const AppError(
      message: 'تعذر معالجة الطلب، يرجى المحاولة مجدداً',
      type: AppErrorType.server,
    );
  }

  /// Turns the model's ref-keyed answer into the id-keyed result the rest of the
  /// app already knows how to render. Identical in shape to what the edge
  /// function returned, so nothing downstream changed.
  static ItemMatchResult _toResult(String json, ItemMatchCatalog catalog) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The model did not answer with a JSON object');
    }

    final matches = <MatchedItem>[];
    for (final raw in decoded['matches'] as List? ?? const []) {
      if (raw is! Map) continue;
      final itemId = catalog.idByRef(raw['item_ref']);
      final quantity = (raw['quantity'] as num?)?.toDouble() ?? 0;
      if (itemId == null || quantity <= 0) continue;
      matches.add(MatchedItem(
        itemId: itemId,
        quantity: quantity,
        confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
      ));
    }

    final unmatched = <UnmatchedItem>[];
    for (final raw in decoded['unmatched'] as List? ?? const []) {
      if (raw is! Map) continue;
      final text = raw['text'] as String?;
      if (text == null || text.trim().isEmpty) continue;
      unmatched.add(UnmatchedItem(
        text: text,
        quantity: (raw['quantity'] as num?)?.toDouble(),
        unit: raw['unit'] as String?,
      ));
    }

    final ambiguous = <AmbiguousItem>[];
    for (final raw in decoded['ambiguous'] as List? ?? const []) {
      if (raw is! Map) continue;
      final text = raw['text'] as String?;
      if (text == null || text.trim().isEmpty) continue;
      final quantity = (raw['quantity'] as num?)?.toDouble();
      final unit = raw['unit'] as String?;
      // Deduped: the same row offered twice would render as two identical
      // choices in the review sheet, which reads as a bug.
      final candidateIds = <String>{
        for (final ref in raw['candidate_item_refs'] as List? ?? const [])
          ?catalog.idByRef(ref),
      }.take(4).toList();

      if (candidateIds.length >= 2) {
        ambiguous.add(AmbiguousItem(
          text: text,
          quantity: quantity,
          unit: unit,
          candidateItemIds: candidateIds,
        ));
      } else if (candidateIds.length == 1) {
        // Nothing left to disambiguate — it's a real match.
        matches.add(MatchedItem(
          itemId: candidateIds.single,
          quantity: quantity == null || quantity <= 0 ? 1 : quantity,
          confidence: 1,
        ));
      } else {
        // No valid candidates survived — falls back to unmatched.
        unmatched.add(UnmatchedItem(text: text, quantity: quantity, unit: unit));
      }
    }

    return ItemMatchResult(
      matches: matches,
      unmatched: unmatched,
      ambiguous: ambiguous,
      heardSummary: decoded['heard_summary'] as String?,
    );
  }
}
