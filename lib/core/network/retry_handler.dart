import '../errors/app_result.dart';
import '../logging/app_logger.dart';

/// Retries [fn] up to [maxAttempts] times with exponential backoff.
/// Returns the first success or the last failure if all attempts fail.
Future<AppResult<T>> withRetry<T>(
  Future<AppResult<T>> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  AppResult<T>? last;
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    last = await fn();
    if (last is AppSuccess<T>) return last;
    if (attempt < maxAttempts) {
      final delay = initialDelay * attempt;
      logger.w('withRetry → attempt $attempt failed, retrying in ${delay.inSeconds}s');
      await Future.delayed(delay);
    }
  }
  return last!;
}
