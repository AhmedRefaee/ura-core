import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/app_logger.dart';

/// Turns a stored file reference in a private bucket into a short-lived
/// signed URL (the bucket's org-scoped SELECT policy decides who gets one).
///
/// Accepts both storage paths ("orgId/…/file.pdf", what is stored now) and
/// the full public URLs stored before the buckets were made private.
class SignedStorageUrl {
  SignedStorageUrl._();

  static const _lifetime = Duration(hours: 1);
  static final _cache = <String, (DateTime, String)>{};

  static Future<String?> resolve(String bucket, String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    final path = pathOf(bucket, stored);
    final key = '$bucket/$path';
    final hit = _cache[key];
    // Reuse until 5 minutes before expiry.
    if (hit != null && DateTime.now().isBefore(hit.$1)) return hit.$2;
    try {
      final url = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(path, _lifetime.inSeconds);
      _cache[key] = (DateTime.now().add(_lifetime - const Duration(minutes: 5)), url);
      return url;
    } catch (e, st) {
      logger.e('SignedStorageUrl → $bucket/$path failed', error: e, stackTrace: st);
      return null;
    }
  }

  static String pathOf(String bucket, String stored) {
    if (!stored.startsWith('http')) return stored;
    final marker = '/$bucket/';
    final i = stored.indexOf(marker);
    if (i < 0) return stored;
    return Uri.decodeComponent(stored.substring(i + marker.length).split('?').first);
  }
}
