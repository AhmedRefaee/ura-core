/// Destination for diagnostics that have to outlive the current process.
///
/// [AppLogger] talks to this instead of to Firebase directly, so logging stays
/// usable anywhere Firebase was never initialized — unit tests, widget tests,
/// and any tooling entrypoint. The no-op implementation is the default and the
/// Crashlytics-backed one is installed from `main()` after `Firebase.initializeApp`.
abstract class CrashReporter {
  const CrashReporter();

  /// Reports a non-fatal error. [reason] is the human-readable context that
  /// gets shown as the report's title.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  });

  /// Breadcrumb attached to whatever error is reported next. Use for the trail
  /// leading up to a failure, not for the failure itself.
  Future<void> log(String message);

  /// Ties subsequent reports to a user, so a phone call from a warehouse can be
  /// traced to their actual crashes. Pass null on sign-out.
  Future<void> setUserId(String? userId);
}

/// Default reporter — drops everything. Keeps [AppLogger] side-effect free
/// until a real reporter is installed.
class NoopCrashReporter extends CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setUserId(String? userId) async {}
}
