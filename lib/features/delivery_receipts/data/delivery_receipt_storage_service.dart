import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';

/// Uploads a generated سند PDF to the `delivery-receipts` bucket.
///
/// Uploaded before the receipt row exists (so pdf_url can be set at INSERT
/// and the row never needs an UPDATE), hence keyed by the uploader rather
/// than a receipt id. The first path segment must be the organization_id --
/// the bucket's RLS scopes on it.
class DeliveryReceiptStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _bucket = 'delivery-receipts';

  Future<AppResult<String>> uploadPdf(Uint8List bytes) async {
    try {
      final uid = _supabase.auth.currentUser!.id;
      final profile = await _supabase
          .from('profiles')
          .select('organization_id')
          .eq('id', uid)
          .single();
      final orgId = profile['organization_id'] as String;
      final path = '$orgId/$uid/${DateTime.now().millisecondsSinceEpoch}.pdf';
      logger.d('DeliveryReceiptStorageService → upload: $path');

      await _supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
          );
      final url = _supabase.storage.from(_bucket).getPublicUrl(path);
      logger.i('DeliveryReceiptStorageService → uploaded → $url');
      return AppSuccess(url);
    } catch (e, st) {
      logger.e('DeliveryReceiptStorageService → upload failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
