import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/core/network/retry_handler.dart';

const _networkError = AppError(
  message: 'تحقق من اتصالك بالإنترنت',
  type: AppErrorType.network,
);

void main() {
  group('withRetry', () {
    // ─── No retry needed ──────────────────────────────────────────────────────
    test('returns success immediately without retrying', () async {
      int calls = 0;
      final result = await withRetry(() async {
        calls++;
        return const AppSuccess(42);
      });
      expect(result, isA<AppSuccess<int>>());
      expect((result as AppSuccess<int>).data, 42);
      expect(calls, 1);
    });

    // ─── Slow internet — success after retry ──────────────────────────────────
    test('retries on failure and returns success on second attempt', () {
      fakeAsync((async) {
        int calls = 0;
        AppResult<int>? result;

        withRetry<int>(
          () async {
            calls++;
            if (calls == 1) return const AppFailure(_networkError);
            return const AppSuccess(99);
          },
          maxAttempts: 3,
          initialDelay: const Duration(seconds: 1),
        ).then((r) => result = r);

        // Delay after attempt 1 is 1 s; elapse enough for it to fire
        async.elapse(const Duration(seconds: 2));

        expect(result, isA<AppSuccess<int>>());
        expect((result as AppSuccess<int>).data, 99);
        expect(calls, 2);
      });
    });

    // ─── All attempts fail ────────────────────────────────────────────────────
    test('returns last failure when all attempts fail', () {
      fakeAsync((async) {
        int calls = 0;
        AppResult<int>? result;

        withRetry<int>(
          () async {
            calls++;
            return const AppFailure(_networkError);
          },
          maxAttempts: 3,
          initialDelay: const Duration(seconds: 1),
        ).then((r) => result = r);

        // Delays: 1 s after attempt 1, 2 s after attempt 2 → 3 s total
        async.elapse(const Duration(seconds: 4));

        expect(result, isA<AppFailure<int>>());
        expect((result as AppFailure<int>).error.type, AppErrorType.network);
        expect(calls, 3);
      });
    });

    // ─── Custom maxAttempts ───────────────────────────────────────────────────
    test('respects custom maxAttempts', () {
      fakeAsync((async) {
        int calls = 0;

        withRetry<int>(
          () async {
            calls++;
            return const AppFailure(_networkError);
          },
          maxAttempts: 5,
          initialDelay: const Duration(milliseconds: 100),
        ).then((_) {});

        // Sum of delays: 100 + 200 + 300 + 400 = 1000 ms
        async.elapse(const Duration(seconds: 2));

        expect(calls, 5);
      });
    });

    // ─── Single attempt ───────────────────────────────────────────────────────
    test('maxAttempts=1 does not retry', () async {
      int calls = 0;
      final result = await withRetry<int>(
        () async {
          calls++;
          return const AppFailure(_networkError);
        },
        maxAttempts: 1,
      );
      expect(result, isA<AppFailure<int>>());
      expect(calls, 1);
    });
  });
}
