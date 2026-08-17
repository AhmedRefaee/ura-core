import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/voice_match_result.dart';

class VoiceMatchRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Sends a recorded audio clip to the voice-match-items edge function,
  /// which transcribes and matches it in a single multimodal call against
  /// the caller's own inventory (RLS-scoped), returning only matches backed
  /// by real inventory rows, plus anything unmatched.
  Future<AppResult<VoiceMatchResult>> matchVoiceAudio(Uint8List audioBytes, String mimeType) async {
    try {
      logger.d('VoiceMatchRepository → matchVoiceAudio: ${audioBytes.length} bytes');
      final started = DateTime.now();
      final response = await _supabase.functions.invoke(
        'voice-match-items',
        body: {
          'audio_base64': base64Encode(audioBytes),
          'mime_type': mimeType,
        },
      );
      final roundTripMs = DateTime.now().difference(started).inMilliseconds;
      final data = response.data as Map<String, dynamic>;
      // Temporary instrumentation to find where request latency actually goes,
      // since this debug log is the only practical visibility we have without
      // extra tooling. serverTiming is set by the edge function itself; the
      // gap between roundTripMs and serverTiming.total is network transfer time.
      logger.d('VoiceMatchRepository → roundTripMs: $roundTripMs, serverTiming: ${data['debug_timing_ms']}');
      final result = VoiceMatchResult.fromMap(data);
      logger.i(
        'VoiceMatchRepository → ${result.matches.length} matches, ${result.unmatched.length} unmatched',
      );
      return AppSuccess(result);
    } catch (e, st) {
      logger.e('VoiceMatchRepository → matchVoiceAudio failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
