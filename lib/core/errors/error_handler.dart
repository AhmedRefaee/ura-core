import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_error.dart';

class ErrorHandler {
  /// Maps any exception to an [AppError] with an Arabic user-facing message.
  static AppError handle(dynamic error) {
    if (error is AuthException) return _handleAuth(error);
    if (error is PostgrestException) return _handlePostgrest(error);
    if (error is StorageException) {
      return const AppError(
        message: 'حدث خطأ في رفع الملف، يرجى المحاولة مجدداً',
        type: AppErrorType.server,
      );
    }
    if (error is SocketException) {
      return const AppError(
        message: 'تحقق من اتصالك بالإنترنت',
        type: AppErrorType.network,
      );
    }
    if (error is Exception) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      if (_containsArabic(msg)) {
        return AppError(message: msg, type: AppErrorType.server);
      }
    }
    return const AppError(
      message: 'حدث خطأ غير متوقع، يرجى المحاولة مجدداً',
      type: AppErrorType.unknown,
    );
  }

  /// Reads the `{'success': false, 'error': '...'}` RPC response shape.
  static AppError fromRpcResult(Map<dynamic, dynamic> result) {
    final msg = result['error'] as String? ?? '';
    if (msg.isNotEmpty) {
      return AppError(
        message: msg,
        type: AppErrorType.server,
      );
    }
    return const AppError(
      message: 'حدث خطأ في العملية، يرجى المحاولة مجدداً',
      type: AppErrorType.server,
    );
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  static AppError _handleAuth(AuthException error) {
    final msg = error.message.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password') ||
        msg.contains('invalid password')) {
      return const AppError(
        message: 'البريد الإلكتروني أو كلمة المرور غير صحيحة',
        type: AppErrorType.auth,
      );
    }
    if (msg.contains('email not confirmed') ||
        msg.contains('email address not confirmed')) {
      return const AppError(
        message: 'يرجى تأكيد بريدك الإلكتروني أولاً',
        type: AppErrorType.auth,
      );
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return const AppError(
        message: 'هذا البريد الإلكتروني مسجل مسبقاً',
        type: AppErrorType.validation,
      );
    }
    if (msg.contains('jwt') ||
        msg.contains('token') ||
        msg.contains('expired') ||
        msg.contains('session_not_found') ||
        msg.contains('refresh_token_not_found')) {
      return const AppError(
        message: 'انتهت جلستك، يرجى تسجيل الدخول مجدداً',
        type: AppErrorType.sessionExpired,
      );
    }
    if (msg.contains('weak password') || msg.contains('password should')) {
      return const AppError(
        message: 'كلمة المرور ضعيفة، يرجى اختيار كلمة مرور أقوى',
        type: AppErrorType.validation,
      );
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return const AppError(
        message: 'محاولات كثيرة، يرجى الانتظار قليلاً ثم المحاولة مجدداً',
        type: AppErrorType.server,
      );
    }
    // Pass through Arabic messages coming from the backend directly
    if (_containsArabic(error.message)) {
      return AppError(message: error.message, type: AppErrorType.auth);
    }
    return const AppError(
      message: 'حدث خطأ في المصادقة، يرجى المحاولة مجدداً',
      type: AppErrorType.auth,
    );
  }

  static AppError _handlePostgrest(PostgrestException error) {
    // Standard Postgres error codes
    switch (error.code) {
      case '23505':
        return const AppError(
          message: 'هذا العنصر موجود مسبقاً',
          type: AppErrorType.validation,
        );
      case '23503':
        return const AppError(
          message: 'لا يمكن تنفيذ العملية، العنصر مرتبط ببيانات أخرى',
          type: AppErrorType.validation,
        );
      case '42501':
        return const AppError(
          message: 'ليس لديك صلاحية للقيام بهذه العملية',
          type: AppErrorType.permission,
        );
      case 'PGRST116':
        return const AppError(
          message: 'لم يتم العثور على النتيجة المطلوبة',
          type: AppErrorType.notFound,
        );
    }
    // JWT/session expiry coming through Postgrest
    final msg = error.message.toLowerCase();
    if (msg.contains('jwt') || msg.contains('expired')) {
      return const AppError(
        message: 'انتهت جلستك، يرجى تسجيل الدخول مجدداً',
        type: AppErrorType.sessionExpired,
      );
    }
    if (_containsArabic(error.message)) {
      return AppError(message: error.message, type: AppErrorType.server);
    }
    return const AppError(
      message: 'حدث خطأ في الخادم، يرجى المحاولة مجدداً',
      type: AppErrorType.server,
    );
  }

  static bool _containsArabic(String text) =>
      RegExp(r'[؀-ۿ]').hasMatch(text);
}
