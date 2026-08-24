import 'dart:async';

/// Reports how long a realtime session has been running on a fixed cadence.
///
/// Elapsed time is derived from the periodic timer's own tick count, which the
/// runtime recomputes from real time, so a throttled or delayed timer still
/// reports the duration the user actually waited.
///
/// [start] replaces any previous run, so a restarted session cannot leave an
/// orphaned timer behind.
final class SessionElapsedClock {
  SessionElapsedClock({this.tick = const Duration(seconds: 1)});

  final Duration tick;

  Timer? _timer;

  bool get isRunning => _timer != null;

  void start(void Function(Duration elapsed) onTick) {
    stop();
    _timer = Timer.periodic(tick, (timer) => onTick(tick * timer.tick));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
