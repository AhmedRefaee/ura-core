import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/error_handler.dart';

void main() {
  group('ErrorHandler', () {
    // ─── No internet ────────────────────────────────────────────────────────
    group('network errors', () {
      test('SocketException → network type', () {
        final error = ErrorHandler.handle(const SocketException('unreachable'));
        expect(error.type, AppErrorType.network);
        expect(error.message, 'تحقق من اتصالك بالإنترنت');
      });

      test('ClientException → network type', () {
        final error = ErrorHandler.handle(http.ClientException('failed'));
        expect(error.type, AppErrorType.network);
        expect(error.message, 'تحقق من اتصالك بالإنترنت');
      });
    });

    // ─── Wrong login ─────────────────────────────────────────────────────────
    group('wrong login', () {
      test('invalid login credentials message → auth type', () {
        final error = ErrorHandler.handle(
          const AuthException('invalid login credentials'),
        );
        expect(error.type, AppErrorType.auth);
        expect(error.message, 'البريد الإلكتروني أو كلمة المرور غير صحيحة');
      });

      test('invalid password message → auth type', () {
        final error = ErrorHandler.handle(
          const AuthException('invalid password'),
        );
        expect(error.type, AppErrorType.auth);
        expect(error.message, 'البريد الإلكتروني أو كلمة المرور غير صحيحة');
      });

      test('invalid email or password message → auth type', () {
        final error = ErrorHandler.handle(
          const AuthException('invalid email or password'),
        );
        expect(error.type, AppErrorType.auth);
        expect(error.message, 'البريد الإلكتروني أو كلمة المرور غير صحيحة');
      });

      test('email not confirmed → auth type', () {
        final error = ErrorHandler.handle(
          const AuthException('email not confirmed'),
        );
        expect(error.type, AppErrorType.auth);
        expect(error.message, 'يرجى تأكيد بريدك الإلكتروني أولاً');
      });

      test('already registered → validation type', () {
        final error = ErrorHandler.handle(
          const AuthException('user already registered'),
        );
        expect(error.type, AppErrorType.validation);
        expect(error.message, 'هذا البريد الإلكتروني مسجل مسبقاً');
      });

      test('weak password → validation type', () {
        final error = ErrorHandler.handle(const AuthException('weak password'));
        expect(error.type, AppErrorType.validation);
        expect(
          error.message,
          'كلمة المرور ضعيفة، يرجى اختيار كلمة مرور أقوى',
        );
      });

      test('rate limited → server type', () {
        final error =
            ErrorHandler.handle(const AuthException('too many requests'));
        expect(error.type, AppErrorType.server);
        expect(
          error.message,
          'محاولات كثيرة، يرجى الانتظار قليلاً ثم المحاولة مجدداً',
        );
      });
    });

    // ─── Expired session ─────────────────────────────────────────────────────
    group('expired session', () {
      test('AuthException: jwt → sessionExpired type', () {
        final error = ErrorHandler.handle(const AuthException('jwt expired'));
        expect(error.type, AppErrorType.sessionExpired);
        expect(error.message, 'انتهت جلستك، يرجى تسجيل الدخول مجدداً');
      });

      test('AuthException: token expired → sessionExpired type', () {
        final error =
            ErrorHandler.handle(const AuthException('token has expired'));
        expect(error.type, AppErrorType.sessionExpired);
        expect(error.message, 'انتهت جلستك، يرجى تسجيل الدخول مجدداً');
      });

      test('AuthException: refresh_token_not_found → sessionExpired type', () {
        final error = ErrorHandler.handle(
          const AuthException('refresh_token_not_found'),
        );
        expect(error.type, AppErrorType.sessionExpired);
        expect(error.message, 'انتهت جلستك، يرجى تسجيل الدخول مجدداً');
      });

      test('AuthException: session_not_found → sessionExpired type', () {
        final error = ErrorHandler.handle(
          const AuthException('session_not_found'),
        );
        expect(error.type, AppErrorType.sessionExpired);
        expect(error.message, 'انتهت جلستك، يرجى تسجيل الدخول مجدداً');
      });

      test('PostgrestException: jwt expired message → sessionExpired type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'JWT expired', code: null),
        );
        expect(error.type, AppErrorType.sessionExpired);
        expect(error.message, 'انتهت جلستك، يرجى تسجيل الدخول مجدداً');
      });
    });

    // ─── Permission denied ───────────────────────────────────────────────────
    group('permission denied', () {
      test('PostgrestException 42501 → permission type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'permission denied for table orders', code: '42501'),
        );
        expect(error.type, AppErrorType.permission);
        expect(error.message, 'ليس لديك صلاحية للقيام بهذه العملية');
      });
    });

    // ─── Empty data / not found ───────────────────────────────────────────────
    group('not found', () {
      test('PostgrestException PGRST116 → notFound type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'row not found', code: 'PGRST116'),
        );
        expect(error.type, AppErrorType.notFound);
        expect(error.message, 'لم يتم العثور على النتيجة المطلوبة');
      });
    });

    // ─── Supabase / server errors ─────────────────────────────────────────────
    group('supabase server errors', () {
      test('PostgrestException generic → server type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'internal server error', code: null),
        );
        expect(error.type, AppErrorType.server);
        expect(error.message, 'حدث خطأ في الخادم، يرجى المحاولة مجدداً');
      });

      test('PostgrestException 23505 duplicate → validation type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'duplicate key value', code: '23505'),
        );
        expect(error.type, AppErrorType.validation);
        expect(error.message, 'هذا العنصر موجود مسبقاً');
      });

      test('PostgrestException 23503 foreign key → validation type', () {
        final error = ErrorHandler.handle(
          PostgrestException(message: 'foreign key violation', code: '23503'),
        );
        expect(error.type, AppErrorType.validation);
        expect(
          error.message,
          'لا يمكن تنفيذ العملية، العنصر مرتبط ببيانات أخرى',
        );
      });
    });

    // ─── Upload failure ───────────────────────────────────────────────────────
    group('upload failure', () {
      test('StorageException → server type with upload message', () {
        final error =
            ErrorHandler.handle(const StorageException('upload failed'));
        expect(error.type, AppErrorType.server);
        expect(error.message, 'حدث خطأ في رفع الملف، يرجى المحاولة مجدداً');
      });
    });

    // ─── Duplicate action ─────────────────────────────────────────────────────
    // Covered above by PostgrestException 23505 test.

    // ─── Unknown errors ───────────────────────────────────────────────────────
    group('unknown errors', () {
      test('unrecognised Exception → unknown type', () {
        final error = ErrorHandler.handle(Exception('something unexpected'));
        expect(error.type, AppErrorType.unknown);
        expect(error.message, 'حدث خطأ غير متوقع، يرجى المحاولة مجدداً');
      });
    });

    // ─── fromRpcResult ────────────────────────────────────────────────────────
    group('fromRpcResult', () {
      test('non-empty error string → server type with that message', () {
        final error = ErrorHandler.fromRpcResult({
          'success': false,
          'error': 'يجب إضافة عنصر واحد على الأقل',
        });
        expect(error.type, AppErrorType.server);
        expect(error.message, 'يجب إضافة عنصر واحد على الأقل');
      });

      test('empty error string → fallback server message', () {
        final error =
            ErrorHandler.fromRpcResult({'success': false, 'error': ''});
        expect(error.type, AppErrorType.server);
        expect(error.message.isNotEmpty, true);
      });

      test('missing error key → fallback server message', () {
        final error = ErrorHandler.fromRpcResult({'success': false});
        expect(error.type, AppErrorType.server);
        expect(error.message.isNotEmpty, true);
      });
    });
  });
}
