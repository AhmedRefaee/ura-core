import 'app_error.dart';

sealed class AppResult<T> {
  const AppResult();
}

final class AppSuccess<T> extends AppResult<T> {
  final T data;
  const AppSuccess(this.data);
}

final class AppFailure<T> extends AppResult<T> {
  final AppError error;
  const AppFailure(this.error);
}

extension AppResultX<T> on AppResult<T> {
  /// Returns the [AppError] if this is a failure, otherwise null.
  AppError? get failureOrNull => switch (this) {
        AppFailure(:final error) => error,
        AppSuccess() => null,
      };
}
