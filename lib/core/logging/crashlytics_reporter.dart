import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'crash_reporter.dart';

/// [CrashReporter] backed by Firebase Crashlytics.
///
/// Only instantiate this after `Firebase.initializeApp` has completed —
/// everything else in the app should depend on [CrashReporter], not on this.
class CrashlyticsReporter extends CrashReporter {
  CrashlyticsReporter([FirebaseCrashlytics? crashlytics])
      : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) =>
      _crashlytics.recordError(error, stack, reason: reason, fatal: fatal);

  @override
  Future<void> log(String message) => _crashlytics.log(message);

  @override
  Future<void> setUserId(String? userId) =>
      _crashlytics.setUserIdentifier(userId ?? '');
}
