import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/logging/app_logger.dart';
import 'package:ura_core/core/logging/crash_reporter.dart';

class _RecordedError {
  const _RecordedError(this.error, this.stack, this.reason, this.fatal);

  final Object error;
  final StackTrace? stack;
  final String? reason;
  final bool fatal;
}

class _FakeCrashReporter extends CrashReporter {
  final errors = <_RecordedError>[];
  final breadcrumbs = <String>[];
  final userIds = <String?>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    errors.add(_RecordedError(error, stack, reason, fatal));
  }

  @override
  Future<void> log(String message) async => breadcrumbs.add(message);

  @override
  Future<void> setUserId(String? userId) async => userIds.add(userId);
}

void main() {
  late _FakeCrashReporter reporter;

  setUp(() {
    reporter = _FakeCrashReporter();
    logger.useCrashReporter(reporter);
    // `logger` is a global singleton, so leaving a fake installed would leak
    // into every test file that runs after this one.
    addTearDown(() => logger.useCrashReporter(const NoopCrashReporter()));
  });

  group('AppLogger crash forwarding', () {
    test('e() reports the original error, stack and message', () {
      final error = StateError('inventory went negative');
      final stack = StackTrace.current;

      logger.e('storage approval failed', error: error, stackTrace: stack);

      expect(reporter.errors, hasLength(1));
      final recorded = reporter.errors.single;
      expect(recorded.error, same(error));
      expect(recorded.stack, same(stack));
      expect(recorded.reason, 'storage approval failed');
      expect(recorded.fatal, isFalse);
    });

    test('e() falls back to the message when no error object is given', () {
      logger.e('something went wrong');

      expect(reporter.errors.single.error, 'something went wrong');
    });

    test('w() records a breadcrumb rather than an error', () {
      logger.w('retrying order fetch', extra: 'attempt 2');

      expect(reporter.errors, isEmpty);
      expect(reporter.breadcrumbs.single, contains('retrying order fetch'));
      expect(reporter.breadcrumbs.single, contains('attempt 2'));
    });

    test('d() and i() stay local and never reach the reporter', () {
      logger.d('debug detail');
      logger.i('app started');

      expect(reporter.errors, isEmpty);
      expect(reporter.breadcrumbs, isEmpty);
    });
  });

  test('NoopCrashReporter accepts every call without throwing', () async {
    const noop = NoopCrashReporter();

    await expectLater(
      Future.wait([
        noop.recordError(Exception('x'), StackTrace.current),
        noop.log('breadcrumb'),
        noop.setUserId('user-1'),
        noop.setUserId(null),
      ]),
      completes,
    );
  });
}
