enum AppErrorType {
  auth,
  sessionExpired,
  notFound,
  permission,
  validation,
  server,
  network,
  unknown,
}

class AppError {
  final String message;
  final AppErrorType type;

  const AppError({required this.message, required this.type});
}
