import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'crash_reporter.dart';

final logger = AppLogger._instance;

class AppLogger {
  AppLogger._();

  static final AppLogger _instance = AppLogger._();

  final _logger = Logger(
    filter: _DebugOnlyFilter(),
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 8,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  CrashReporter _crashReporter = const NoopCrashReporter();

  /// Installs the reporter that warnings and errors are forwarded to. Called
  /// from `main()` once Firebase is up; tests leave the no-op default in place.
  // ignore: use_setters_to_change_properties
  void useCrashReporter(CrashReporter reporter) => _crashReporter = reporter;

  CrashReporter get crashReporter => _crashReporter;

  void d(String message, {Object? extra}) =>
      _logger.d(extra != null ? '$message\n$extra' : message);

  void i(String message, {Object? extra}) =>
      _logger.i(extra != null ? '$message\n$extra' : message);

  /// Console output is debug-only, but the breadcrumb is recorded in every
  /// build — warnings are usually the trail leading up to a crash.
  void w(String message, {Object? extra}) {
    final text = extra != null ? '$message\n$extra' : message;
    _logger.w(text);
    unawaited(_crashReporter.log('WARN $text'));
  }

  /// Reported to the crash reporter in every build, including release, where
  /// the console sink below is switched off.
  void e(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    unawaited(
      _crashReporter.recordError(error ?? message, stackTrace, reason: message),
    );
  }
}

/// Gates the *console* sink only. Crash reporting is deliberately not behind
/// this — release builds have no console worth printing to, which is exactly
/// when the remote report matters most.
class _DebugOnlyFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => kDebugMode;
}
