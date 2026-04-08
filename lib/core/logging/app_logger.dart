import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

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

  void d(String message, {Object? extra}) =>
      _logger.d(extra != null ? '$message\n$extra' : message);

  void i(String message, {Object? extra}) =>
      _logger.i(extra != null ? '$message\n$extra' : message);

  void w(String message, {Object? extra}) =>
      _logger.w(extra != null ? '$message\n$extra' : message);

  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}

class _DebugOnlyFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => kDebugMode;
}
 