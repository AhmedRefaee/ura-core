import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';

class ChatStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _bucket = 'chat-attachments';

  Future<AppResult<String>> uploadAttachment({
    required String threadId,
    required String localPath,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      logger.d('ChatStorageService → upload: $fileName');
      final uid = _supabase.auth.currentUser?.id ?? 'unknown';
      final ext = fileName.contains('.') ? fileName.split('.').last : '';
      final storagePath =
          '$threadId/$uid/${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? '.$ext' : ''}';

      await _supabase.storage.from(_bucket).upload(
            storagePath,
            File(localPath),
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );

      final url = _supabase.storage.from(_bucket).getPublicUrl(storagePath);
      logger.i('ChatStorageService → uploaded → $url');
      return AppSuccess(url);
    } catch (e, st) {
      logger.e('ChatStorageService → upload failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<void>> deleteAttachment(String publicUrl) async {
    try {
      final uri = Uri.parse(publicUrl);
      // Path after /object/public/chat-attachments/
      final segments = uri.pathSegments;
      final bucketIdx = segments.indexOf(_bucket);
      if (bucketIdx == -1) return const AppSuccess(null);
      final path = segments.sublist(bucketIdx + 1).join('/');
      await _supabase.storage.from(_bucket).remove([path]);
      return const AppSuccess(null);
    } catch (e, st) {
      logger.e('ChatStorageService → delete failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
