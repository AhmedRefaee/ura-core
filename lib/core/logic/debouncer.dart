import 'dart:async';

/// Collapses a burst of calls into one, run [delay] after the last.
///
/// Realtime channels fire once per changed row, so a single bulk edit or
/// status change can mean several events in a few milliseconds; each used
/// to trigger its own full refetch.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer([this.delay = const Duration(milliseconds: 400)]);

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();
}
