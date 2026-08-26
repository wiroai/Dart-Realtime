import 'dart:async';

import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';

/// Retry and auto-restart budgets for a conversation that lost its task.
///
/// In-flight retries belong to one start attempt. Auto-restarts are the
/// page doing what relaunching the app would do, after that budget is
/// spent. A healthy microphone chunk reaching the server is the only
/// signal that both counters should refill.
final class ConversationRecoveryPolicy {
  ConversationRecoveryPolicy({
    this.maxRetryAttempts = 5,
    this.retryBaseDelay = const Duration(milliseconds: 500),
    this.autoRestartDelay = const Duration(seconds: 5),
    this.maxAutoRestarts = 2,
  });

  final int maxRetryAttempts;
  final Duration retryBaseDelay;
  final Duration autoRestartDelay;
  final int maxAutoRestarts;

  Timer? _autoRestartTimer;
  int _retryAttempt = 0;
  int _autoRestartCycle = 0;
  bool _disposed = false;

  /// Count that goes into `retry_scheduled:…` after [noteRetryScheduled].
  int get retryAttempt => _retryAttempt;

  /// Backoff after the current retry was scheduled: doubles each time.
  Duration get nextRetryDelay {
    final multiplier = 1 << (_retryAttempt - 1);
    return retryBaseDelay * multiplier;
  }

  bool shouldRetry(Object error, {required bool isReconfiguring}) {
    if (isReconfiguring || _retryAttempt >= maxRetryAttempts) {
      return false;
    }
    return isRecoverable(error);
  }

  bool isRecoverable(Object error) {
    return switch (error) {
      WiroServerFailure() ||
      WiroNetworkFailure() ||
      WiroTimeoutFailure() ||
      WiroSocketFailure() ||
      WiroSocketConnectTimeoutFailure() ||
      WiroReadyTimeoutFailure() ||
      AudioFailure() => true,
      _ => false,
    };
  }

  void noteRetryScheduled() {
    _retryAttempt++;
  }

  /// A microphone chunk reached the server, so both budgets refill.
  void noteHealthy() {
    _retryAttempt = 0;
    _autoRestartCycle = 0;
  }

  /// A user (or auto-restart) start; in-flight retries reset, the
  /// auto-restart cycle does not — only [noteHealthy] clears that.
  void resetRetries() {
    _retryAttempt = 0;
  }

  /// Arms a restart. Returns false when the budget is spent or the
  /// policy has been disposed.
  bool scheduleAutoRestart(void Function() restart) {
    if (_disposed || _autoRestartCycle >= maxAutoRestarts) {
      return false;
    }
    _autoRestartTimer?.cancel();
    final shift = _autoRestartCycle > 2 ? 2 : _autoRestartCycle;
    _autoRestartCycle++;
    _autoRestartTimer = Timer(autoRestartDelay * (1 << shift), () {
      _autoRestartTimer = null;
      if (_disposed) {
        return;
      }
      restart();
    });
    return true;
  }

  void cancelAutoRestart() {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;
  }

  void dispose() {
    _disposed = true;
    cancelAutoRestart();
  }
}
