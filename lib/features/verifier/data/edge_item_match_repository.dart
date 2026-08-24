
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/models/item_match_result.dart';
import 'item_match_repository.dart';

/// Matches through the `voice-match-items` Supabase edge function, which runs
/// the inventory lookup under the caller's JWT and calls Gemini server-side.
///
/// Superseded by `DirectItemMatchRepository`, which removes two network legs by
/// calling Gemini from the device. Kept wired-but-unused so a single line in
/// `injection.dart` switches back if the Firebase AI Logic path is unavailable
/// — the function is still deployed and still works.
///
/// [inventory] is ignored here: this path fetches its own catalog server-side
/// under RLS. It's on the interface because the direct path genuinely needs it.
class EdgeItemMatchRepository implements ItemMatchRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<AppResult<ItemMatchResult>> matchText(
    String text,
    List<InventoryItem> inventory,
  ) async {
    logger.d('EdgeItemMatchRepository → matchText: ${text.length} chars');
    return _invokeMatch('matchText', {'text': text});
  }

  /// Wakes the edge function while the person is still pasting, so
  /// the real request doesn't also pay for a cold start. Empty input is answered
  /// before the function touches the database or Gemini, which makes it the
  /// cheapest possible way to knock on the door. Fire-and-forget: if it fails,
  /// the real request simply pays the cold start it would have paid anyway.
  @override
  Future<void> warmUp() async {
    try {
      await _supabase.functions.invoke('voice-match-items', body: {'text': ''});
      logger.d('EdgeItemMatchRepository → warmed up');
    } catch (e) {
      logger.d('EdgeItemMatchRepository → warm-up skipped: $e');
    }
  }

  Future<AppResult<ItemMatchResult>> _invokeMatch(
    String label,
    Map<String, dynamic> body,
  ) async {
    try {
      final started = DateTime.now();
      final response =
          await _supabase.functions.invoke('voice-match-items', body: body);
      final roundTripMs = DateTime.now().difference(started).inMilliseconds;
      final data = response.data as Map<String, dynamic>;
      // The gap between roundTripMs and serverTiming.total is the network
      // transfer this path pays and the direct path doesn't.
      logger.d(
        'EdgeItemMatchRepository → $label roundTripMs: $roundTripMs, serverTiming: ${data['debug_timing_ms']}',
      );
      final result = ItemMatchResult.fromMap(data);
      logger.i(
        'EdgeItemMatchRepository → $label ${result.matches.length} matches, ${result.unmatched.length} unmatched',
      );
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('EdgeItemMatchRepository → $label failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
