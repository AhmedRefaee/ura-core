import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/item_match_result.dart';

/// Matches a request for items — spoken or written — against the caller's own
/// inventory. Both inputs go to the same edge function, which runs the lookup
/// under the caller's JWT (so RLS applies) and returns only matches backed by
/// real inventory rows, plus anything it couldn't place.
class ItemMatchRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Sends a recorded audio clip, transcribed and matched in a single
  /// multimodal call.
  Future<AppResult<ItemMatchResult>> matchAudio(Uint8List audioBytes, String mimeType) async {
    logger.d('ItemMatchRepository → matchAudio: ${audioBytes.length} bytes');
    return _invokeMatch('matchAudio', {
      'audio_base64': base64Encode(audioBytes),
      'mime_type': mimeType,
    });
  }

  /// Sends a pasted written request — typically a WhatsApp message forwarded
  /// from someone at an outside entity. Text skips the audio-understanding
  /// pass entirely, so it is the faster of the two inputs.
  Future<AppResult<ItemMatchResult>> matchText(String text) async {
    logger.d('ItemMatchRepository → matchText: ${text.length} chars');
    return _invokeMatch('matchText', {'text': text});
  }

  Future<AppResult<ItemMatchResult>> _invokeMatch(String label, Map<String, dynamic> body) async {
    try {
      final started = DateTime.now();
      final response = await _supabase.functions.invoke('voice-match-items', body: body);
      final roundTripMs = DateTime.now().difference(started).inMilliseconds;
      final data = response.data as Map<String, dynamic>;
      // Temporary instrumentation to find where request latency actually goes,
      // since this debug log is the only practical visibility we have without
      // extra tooling. serverTiming is set by the edge function itself; the
      // gap between roundTripMs and serverTiming.total is network transfer
      // time. The label is what makes audio and text runs comparable in a log.
      logger.d('ItemMatchRepository → $label roundTripMs: $roundTripMs, serverTiming: ${data['debug_timing_ms']}');
      final result = ItemMatchResult.fromMap(data);
      logger.i(
        'ItemMatchRepository → $label ${result.matches.length} matches, ${result.unmatched.length} unmatched',
      );
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('ItemMatchRepository → $label failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
