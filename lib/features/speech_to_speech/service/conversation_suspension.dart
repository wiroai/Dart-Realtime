import 'dart:async';

/// Wall-clock hold for a conversation the speaker left the screen of.
///
/// The timer hangs the task up if nobody comes back. A frozen app runs
/// no timers, so [hasLapsed] is the source of truth on resume: the
/// clock decides whether the speaker is still expected.
final class ConversationSuspension {
  ConversationSuspension({
    required this.gracePeriod,
    required this.onExpired,
  });

  final Duration gracePeriod;
  final void Function() onExpired;

  Timer? _graceTimer;
  DateTime? _suspendedAt;
  bool _disposed = false;

  /// A configured zero (or less) means leaving is hanging up.
  bool get holdsAnything => gracePeriod > Duration.zero;

  /// True when no hold is running, or wall-clock time has passed the
  /// grace period — even if the timer never fired.
  bool get hasLapsed {
    final suspendedAt = _suspendedAt;
    return suspendedAt == null ||
        DateTime.now().difference(suspendedAt) > gracePeriod;
  }

  /// Starts (or restarts) the hold clock.
  void begin() {
    if (_disposed) {
      return;
    }
    _graceTimer?.cancel();
    _suspendedAt = DateTime.now();
    _graceTimer = Timer(gracePeriod, _expire);
  }

  /// Cancels the timer without forgetting when the hold started, so a
  /// resume can still honour a deadline the timer missed.
  void cancel() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  /// Drops the hold entirely: the session is ending or coming back live.
  void clear() {
    cancel();
    _suspendedAt = null;
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _expire() {
    _graceTimer = null;
    if (_disposed) {
      return;
    }
    onExpired();
  }
}
