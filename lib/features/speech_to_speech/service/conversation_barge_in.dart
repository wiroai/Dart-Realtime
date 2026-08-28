import 'dart:async';

import 'package:wiro_realtime/features/speech_to_speech/service/conversation_playback_coordinator.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';

/// Two-stage barge-in: a loud moment silences the assistant while keeping
/// its audio; only input that sustains like speech commits the cut, while
/// a noise burst hands the audio back from where it stopped.
///
/// The hold deadline runs on its own timer so a mute or a stalling mic
/// mid-hold still resolves, rather than waiting on the next chunk.
final class ConversationBargeIn {
  ConversationBargeIn({
    required this.playback,
    required this.voiceActivity,
    required this.onProtocolEvent,
    required this.holdTimeout,
    required this.holdCooldown,
  });

  final ConversationPlaybackCoordinator playback;
  final ConversationVoiceActivity voiceActivity;
  final void Function(String event) onProtocolEvent;
  final Duration holdTimeout;
  final Duration holdCooldown;

  Timer? _interruptHoldTimer;
  DateTime _holdSuppressedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Called by the service after every microphone chunk it accepted.
  void evaluate() {
    if (_disposed) {
      return;
    }
    if (playback.isHolding) {
      if (voiceActivity.userInterrupting) {
        _commitInterruption();
      } else if (!voiceActivity.hasInterruptEvidence) {
        _resumeHeldTurn();
      }
      return;
    }
    if (voiceActivity.userInterrupting) {
      // Reached without a hold only while holds rest after a false alarm;
      // sustained speech still cuts the assistant off.
      _commitInterruption();
      return;
    }
    if (voiceActivity.userMaybeInterrupting &&
        !DateTime.now().isBefore(_holdSuppressedUntil) &&
        playback.holdTurn()) {
      onProtocolEvent('assistant_playback_held');
      _startHoldDeadline();
    }
  }

  /// Cancels the hold deadline without resolving the hold; the caller is
  /// tearing the session down and the coordinator is reset with it.
  void cancelHold() {
    _interruptHoldTimer?.cancel();
    _interruptHoldTimer = null;
  }

  void dispose() {
    _disposed = true;
    cancelHold();
  }

  void _commitInterruption() {
    if (!playback.interruptTurn()) {
      return;
    }
    cancelHold();
    voiceActivity.resetAi();
    onProtocolEvent('assistant_interrupted');
  }

  /// The suspected interruption faded the way noise does: the held
  /// audio goes back to the speaker from the point it was silenced, and
  /// the playback model is rebuilt around what is actually playing now.
  void _resumeHeldTurn() {
    cancelHold();
    final resumed = playback.resumeHeldTurn();
    voiceActivity.resetAi();
    resumed.forEach(voiceActivity.addAiChunk);
    _holdSuppressedUntil = DateTime.now().add(holdCooldown);
    onProtocolEvent('assistant_playback_resumed');
  }

  void _startHoldDeadline() {
    _interruptHoldTimer?.cancel();
    _interruptHoldTimer = Timer(holdTimeout, () {
      _interruptHoldTimer = null;
      if (_disposed || !playback.isHolding) {
        return;
      }
      _resumeHeldTurn();
    });
  }
}
