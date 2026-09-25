import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';

/// Handles delivery receipt PDF upload.
class DeliveryReceiptStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _bucket = 'delivery-receipts';

  Future<AppResult<String>> uploadPdf({
    required String receiptId,
    required String localPath,
    required String fileName,
  }) async {
    try {
      logger.d('DeliveryReceiptStorageService → upload: $fileName for receipt $receiptId');
      final uid = _supabase.auth.currentUser?.id ?? 'unknown';
      final orgId = _supabase.auth.currentUser?.userMetadata?['organization_id'] as String?;

      if (orgId == null) {
        return AppFailure(ErrorHandler.handle(
          Exception('Organization context not found'),
        ));
      }

      final ext = fileName.contains('.') ? fileName.split('.').last : '';
      final storagePath =
          '$orgId/$receiptId/$uid/${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? '.$ext' : ''}';

      await _supabase.storage.from(_bucket).upload(
            storagePath,
            File(localPath),
            fileOptions: FileOptions(contentType: 'application/pdf', upsert: false),
          );

      final url = _supabase.storage.from(_bucket).getPublicUrl(storagePath);
      logger.i('DeliveryReceiptStorageService → uploaded → $url');
      return AppSuccess(url);
    } catch (e, st) {
      logger.e('DeliveryReceiptStorageService → upload failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deletePdf(String publicUrl) async {
    try {
      final uri = Uri.parse(publicUrl);
      final segments = uri.pathSegments;
      final bucketIdx = segments.indexOf(_bucket);
      if (bucketIdx == -1) return const AppSuccess(null);
      final path = segments.sublist(bucketIdx + 1).join('/');
      await _supabase.storage.from(_bucket).remove([path]);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('DeliveryReceiptStorageService → delete failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
