import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/pcm_level_meter.dart';

/// Who owns the conversation at this instant, as far as the ear can tell.
enum ConversationVoicePhase { quiet, userSpeaking, aiSpeaking }

/// Live voice signals for the conversation orb.
///
/// Two kinds of output with two delivery contracts. [phase] is discrete and
/// notifies listeners only when it changes, so widgets can rebuild on it.
/// [userLevel] and [aiLevel] are continuous and silent: they are meant to be
/// polled once per animation frame by the orb's own ticker, so fifty audio
/// chunks a second never schedule a single widget rebuild.
///
/// Assistant audio arrives from the network far faster than it plays.
/// Feeding those chunks straight into a "speaking" flag would end the
/// animation seconds before the voice stops, so this class models the
/// playback pipeline instead: every enqueued chunk extends a playhead by its
/// own duration, and the assistant counts as speaking while the playhead is
/// in the future.
final class ConversationVoiceActivity extends ChangeNotifier {
  /// Normalized level above which a microphone chunk counts as speech.
  static const double _speechThreshold = 0.18;

  /// While the assistant is audible the bar is raised, so speaker bleed
  /// that echo cancellation misses does not read as the user talking.
  static const double _interruptThreshold = 0.45;

  /// How long the user keeps the floor after their last loud chunk, so a
  /// breath between words does not flicker the phase back to quiet.
  static const Duration _userHangover = Duration(milliseconds: 450);

  /// Accumulated loud chunks it takes to suspect an interruption: three
  /// chunks is sixty milliseconds, fast enough that the assistant feels
  /// silenced the instant the user starts talking. The counter leaks
  /// instead of resetting — a loud chunk adds one, a quiet chunk
  /// subtracts one — because genuine speech dips between syllables.
  /// Keeping this trigger-happy is safe because suspicion only pauses
  /// playback: nothing is discarded until [_confirmStreakTarget] proves
  /// the sound is speech, so a keyboard burst costs a beat of silence
  /// rather than the rest of the answer.
  static const int _suspectStreakTarget = 3;

  /// Accumulated loud chunks it takes to call the suspicion speech and
  /// cut the assistant's turn for good. A keyboard click is a couple of
  /// loud chunks drowning in their own gaps, so the leaking counter
  /// cannot climb this far on typing; a spoken sentence keeps the
  /// counter fed through its syllable dips and crosses within roughly a
  /// quarter of a second.
  static const int _confirmStreakTarget = 8;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Segments arrive and expire in time order, so pruning always pops
  /// from the front and never scans the whole backlog a bursty server
  /// may have queued.
  final Queue<_AiAudioSegment> _aiSegments = Queue<_AiAudioSegment>();
  double _userLevel = 0;
  int _interruptStreak = 0;
  DateTime _userActiveUntil = _epoch;
  DateTime _aiPlayheadUntil = _epoch;
  ConversationVoicePhase _phase = ConversationVoicePhase.quiet;
  Timer? _phaseTimer;
  bool _disposed = false;

  ConversationVoicePhase get phase => _phase;

  /// Smoothed microphone level, 0..1. Poll per frame; never notifies.
  double get userLevel => _userLevel;

  /// True while queued assistant audio is still playing through the
  /// speaker, which is exactly when microphone input may carry echo.
  bool get aiAudioPending => DateTime.now().isBefore(_aiPlayheadUntil);

  /// True while the user has been loud over pending assistant audio just
  /// long enough to be either speech or a slammed key: worth silencing
  /// the assistant, not yet worth discarding its audio.
  bool get userMaybeInterrupting {
    return _interruptStreak >= _suspectStreakTarget &&
        DateTime.now().isBefore(_aiPlayheadUntil);
  }

  /// True once loud input over pending assistant audio has sustained the
  /// way only speech does, so the assistant's turn can be cut for good.
  bool get userInterrupting {
    return _interruptStreak >= _confirmStreakTarget &&
        DateTime.now().isBefore(_aiPlayheadUntil);
  }

  /// True while recent chunks still argue for an interruption; false once
  /// the streak has fully drained, which is how a keyboard click that
  /// paused playback is recognised as noise and taken back.
  bool get hasInterruptEvidence => _interruptStreak > 0;

  /// Level of the assistant audio playing right now, 0..1. Poll per frame.
  double get aiLevel {
    final now = DateTime.now();
    _pruneExpiredSegments(now);
    if (_aiSegments.isEmpty) {
      return 0;
    }
    final head = _aiSegments.first;
    return head.start.isAfter(now) ? 0 : head.level;
  }

  /// Reports one microphone chunk that was sent to the model.
  ///
  /// [level] is the chunk's [pcmNormalizedLevel]; callers that already
  /// measured it — the noise gate does — pass it in so the RMS loop is
  /// not run twice per chunk.
  void addUserChunk(Uint8List chunk, {double? level}) {
    if (_disposed) {
      return;
    }
    level ??= pcmNormalizedLevel(chunk);
    final smoothing = level > _userLevel ? 0.5 : 0.2;
    _userLevel += (level - _userLevel) * smoothing;
    final now = DateTime.now();
    final aiPending = now.isBefore(_aiPlayheadUntil);
    if (!aiPending) {
      _interruptStreak = 0;
    } else if (level >= _interruptThreshold) {
      if (_interruptStreak < _confirmStreakTarget) {
        _interruptStreak++;
      }
    } else if (_interruptStreak > 0) {
      _interruptStreak--;
    }
    final threshold = aiPending ? _interruptThreshold : _speechThreshold;
    if (level >= threshold) {
      _userActiveUntil = now.add(_userHangover);
    }
    _updatePhase(now);
  }

  /// Reports one assistant chunk accepted by the playback queue.
  void addAiChunk(Uint8List chunk) {
    if (_disposed) {
      return;
    }
    final now = DateTime.now();
    _pruneExpiredSegments(now);
    final start = _aiPlayheadUntil.isAfter(now) ? _aiPlayheadUntil : now;
    final end = start.add(_chunkDuration(chunk));
    _aiSegments.add(
      _AiAudioSegment(
        start: start,
        end: end,
        level: pcmNormalizedLevel(chunk),
      ),
    );
    _aiPlayheadUntil = end;
    _updatePhase(now);
  }

  /// Drops segments that have finished playing. They sit at the front of
  /// the queue because segments are created in playback order.
  void _pruneExpiredSegments(DateTime now) {
    while (_aiSegments.isNotEmpty && !_aiSegments.first.end.isAfter(now)) {
      _aiSegments.removeFirst();
    }
  }

  /// Forgets queued assistant audio after the player flushed it.
  void resetAi() {
    if (_disposed) {
      return;
    }
    _aiSegments.clear();
    _aiPlayheadUntil = _epoch;
    _updatePhase(DateTime.now());
  }

  /// Forgets microphone activity after capture was muted or stopped.
  void resetUser() {
    if (_disposed) {
      return;
    }
    _userLevel = 0;
    _interruptStreak = 0;
    _userActiveUntil = _epoch;
    _updatePhase(DateTime.now());
  }

  void reset() {
    if (_disposed) {
      return;
    }
    _aiSegments.clear();
    _aiPlayheadUntil = _epoch;
    _userLevel = 0;
    _interruptStreak = 0;
    _userActiveUntil = _epoch;
    _updatePhase(DateTime.now());
  }

  @override
  void dispose() {
    _disposed = true;
    _phaseTimer?.cancel();
    _phaseTimer = null;
    super.dispose();
  }

  /// The user keeps priority: interrupting the assistant should feel heard
  /// immediately, the same way it does in ChatGPT's voice mode.
  void _updatePhase(DateTime now) {
    final next = now.isBefore(_userActiveUntil)
        ? ConversationVoicePhase.userSpeaking
        : now.isBefore(_aiPlayheadUntil)
        ? ConversationVoicePhase.aiSpeaking
        : ConversationVoicePhase.quiet;
    _schedulePhaseCheck(now);
    if (next == _phase) {
      return;
    }
    _phase = next;
    notifyListeners();
  }

  /// Speaking phases end by time passing, not by an event arriving, so a
  /// one-shot timer re-evaluates the phase at the nearest expiry.
  void _schedulePhaseCheck(DateTime now) {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    final boundaries = [
      _userActiveUntil,
      _aiPlayheadUntil,
    ].where((boundary) => boundary.isAfter(now)).toList();
    if (boundaries.isEmpty) {
      return;
    }
    boundaries.sort();
    _phaseTimer = Timer(
      boundaries.first.difference(now) + const Duration(milliseconds: 20),
      () {
        if (!_disposed) {
          _updatePhase(DateTime.now());
        }
      },
    );
  }

  static Duration _chunkDuration(Uint8List chunk) {
    const bytesPerSecond =
        AudioConstants.sampleRateHz *
        AudioConstants.channelCount *
        AudioConstants.bitsPerSample ~/
        8;
    return Duration(
      microseconds:
          chunk.length * Duration.microsecondsPerSecond ~/ bytesPerSecond,
    );
  }
}

final class _AiAudioSegment {
  const _AiAudioSegment({
    required this.start,
    required this.end,
    required this.level,
  });

  final DateTime start;
  final DateTime end;
  final double level;
}
