import 'package:firebase_ai/firebase_ai.dart';

import '../../../core/logging/app_logger.dart';
import 'item_match_prompt.dart';

/// What one model call cost.
///
/// [unaccounted] is the field worth watching. A device run on 2026-08-24 came
/// back with `thinking=null` against a call that took roughly a minute, which
/// leaves two readings apart: either the model genuinely did not think, or it
/// thought and the SDK did not report it. Totals settle it — whatever the
/// total is over prompt + output + reported thinking is work that was billed
/// and waited on but never named.
class ItemMatchUsage {
  final int? promptTokens;
  final int? outputTokens;
  final int? thinkingTokens;
  final int? totalTokens;
  final int? cachedTokens;

  const ItemMatchUsage({
    this.promptTokens,
    this.outputTokens,
    this.thinkingTokens,
    this.totalTokens,
    this.cachedTokens,
  });

  /// Tokens the total accounts for that nothing else does — invisible thinking,
  /// if it is anything. Null when the total is missing, 0 when it all adds up.
  int? get unaccounted {
    final total = totalTokens;
    if (total == null) return null;
    final named =
        (promptTokens ?? 0) + (outputTokens ?? 0) + (thinkingTokens ?? 0);
    final gap = total - named;
    return gap > 0 ? gap : 0;
  }

  String get summary => 'prompt=$promptTokens output=$outputTokens '
      'thinking=$thinkingTokens total=$totalTokens '
      'cached=$cachedTokens unaccounted=$unaccounted';
}

/// One slice of a streamed answer: some more JSON, and — on the last slice —
/// what the whole call cost.
class ItemMatchModelChunk {
  final String text;
  final ItemMatchUsage? usage;

  const ItemMatchModelChunk({this.text = '', this.usage});
}

/// What the matcher needs from a model and nothing else: hand it the catalog
/// and the request, get JSON back in pieces.
///
/// Streaming rather than a single future on purpose. A `Future.timeout` cannot
/// cancel the request underneath it — the call carries on, billed, while the
/// caller has stopped listening — so a retry built on one does not replace the
/// attempt it is retrying, it races it. A stream subscription genuinely
/// cancels, and the gap between chunks is a far better signal of a stuck call
/// than total elapsed time is.
///
/// Narrow on purpose too: the Firebase SDK stops at this line, which is the
/// only reason the ref mapping, the timeout policy and the failure handling
/// downstream can be tested without a Firebase project.
abstract class ItemMatchModel {
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  });
}

/// Model choices, in one place because they are the two settings most likely to
/// be retuned once real timings come back.
class ItemMatchModels {
  const ItemMatchModels._();

  /// Pinned, not a rolling alias.
  ///
  /// `gemini-flash-latest` was chosen to let Google route around its own
  /// capacity, and that reasoning was wrong in a way that cost a week: an alias
  /// hides which model you are on, and therefore which quota bucket. The free
  /// tier gives Flash 1,500 requests a day where Pro-class models get about a
  /// hundred, so a quota error is undiagnosable while the model is a moving
  /// target. Pinned also means the price per request is a number you can
  /// actually compute.
  ///
  /// Was `gemini-2.5-flash` until 2026-08-31, when a live call came back with
  /// "This model models/gemini-2.5-flash is no longer available to new users."
  /// Google's own error names `gemini-3.6-flash` as the replacement. Being
  /// pinned is what made that a clear one-line error instead of a silent
  /// reroute to an unknown model at an unknown price -- keep it pinned, and
  /// expect to have to do this again.
  static const name = 'gemini-3.6-flash';

  /// This is extraction, not reasoning: read a request, find the names in a
  /// list, report quantities. Gemini 3 models think at `medium` by default, and
  /// every thinking token is generated sequentially with the verifier waiting on
  /// it. [ThinkingLevel.minimal] is the next notch down if the ambiguous
  /// -candidate judgement still holds up without the extra deliberation — see
  /// [ItemMatchUsage.unaccounted] for whether it is costing anything at all.
  static const thinkingLevel = ThinkingLevel.low;
}

/// Calls Gemini straight from the app through Firebase AI Logic.
///
/// This is the point of the whole exercise: the request goes phone → Google
/// rather than phone → Cloudflare → Supabase → Google and back again. No API
/// key ships with the app — App Check vouches for the client instead,
/// activated in `main.dart` — and the catalog is built from inventory already
/// in memory, so the round trip that used to fetch it is gone too.
///
/// App Check enforcement WAS flipped on for the AI Logic service on
/// 2026-08-31, and verified by a real device call: an unattested request now
/// comes back `403 App attestation failed`. Android is the only registered
/// app (Play Integrity in release, a registered debug token in debug); the
/// web app is deliberately unregistered, so web calls are rejected by design.
///
/// If a device starts failing with 403 in debug, it is almost always that
/// build's debug token not being in the allow-list. The SDK prints the token
/// it is actually using to logcat, as a `DebugAppCheckProvider` warning
/// reading "Failed to exchange debug token", followed by the uuid in
/// parentheses. Register THAT uuid — the "generate token" button in the
/// console mints a different one the app knows nothing about.
///
/// Don't trust this comment over the Firebase Console — an earlier version of
/// it asserted enforcement was on when it never had been.
class FirebaseItemMatchModel implements ItemMatchModel {
  final GenerativeModel Function(String systemInstruction) _modelFactory;

  FirebaseItemMatchModel({
    GenerativeModel Function(String systemInstruction)? modelFactory,
  }) : _modelFactory = modelFactory ?? _defaultModel;

  static GenerativeModel _defaultModel(String systemInstruction) {
    return FirebaseAI.googleAI().generativeModel(
      model: ItemMatchModels.name,
      systemInstruction: Content.text(systemInstruction),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: ItemMatchPrompt.responseSchema,
        thinkingConfig: ThinkingConfig.withThinkingLevel(
          ItemMatchModels.thinkingLevel,
        ),
      ),
    );
  }

  @override
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  }) async* {
    final parts = <Part>[
      // The catalog goes first and stays byte-identical between calls while the
      // inventory doesn't change, so it can serve as a cacheable prefix; the
      // part that varies per request follows it.
      TextPart(catalogBlock),
      TextPart('Request message:\n$text'),
    ];

    final responses = _modelFactory(systemInstruction)
        .generateContentStream([Content.multi(parts)]);

    ItemMatchUsage? usage;
    await for (final response in responses) {
      final meta = response.usageMetadata;
      if (meta != null) {
        usage = ItemMatchUsage(
          promptTokens: meta.promptTokenCount,
          outputTokens: meta.candidatesTokenCount,
          thinkingTokens: meta.thoughtsTokenCount,
          totalTokens: meta.totalTokenCount,
          cachedTokens: meta.cachedContentTokenCount,
        );
      }
      yield ItemMatchModelChunk(text: response.text ?? '', usage: usage);
    }

    if (usage != null) {
      logger.d('FirebaseItemMatchModel → model=${ItemMatchModels.name} ${usage.summary}');
    }
  }
}
