import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';

/// Uploads a project's letterhead image to the private `project-letterheads`
/// bucket and returns its storage path (see SignedStorageUrl for reading).
///
/// The path must start with the uploader's organization_id: the bucket's RLS
/// checks that first segment against auth_org_id() (see
/// 20260925120300_delivery_receipt_storage_buckets.sql).
class ProjectStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _bucket = 'project-letterheads';

  Future<AppResult<String>> uploadLetterhead({
    required String projectId,
    required Uint8List bytes,
    required String fileExtension,
    required String mimeType,
  }) async {
    try {
      final uid = _supabase.auth.currentUser!.id;
      final profile = await _supabase
          .from('profiles')
          .select('organization_id')
          .eq('id', uid)
          .single();
      final orgId = profile['organization_id'] as String;
      final path =
          '$orgId/$projectId/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      logger.d('ProjectStorageService → upload letterhead: $path');

      await _supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      logger.i('ProjectStorageService → uploaded → $path');
      // The bucket is private: store the path; readers get a signed URL.
      return AppSuccess(path);
    } catch (e, st) {
      logger.e('ProjectStorageService → upload failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
