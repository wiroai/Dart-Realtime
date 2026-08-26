import 'dart:collection';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';

/// What happened to a chunk of assistant audio on its way to the speaker.
///
/// The two outcomes are independent: a chunk can clear an interrupted turn and
/// still be dropped by a full queue.
final class PlaybackEnqueueResult {
  const PlaybackEnqueueResult({
    required this.flushedPreviousTurn,
    required this.droppedChunk,
    this.silencedChunk = false,
    this.heldChunk = false,
  });

  final bool flushedPreviousTurn;
  final bool droppedChunk;

  /// The chunk belonged to a turn the user talked over and was discarded
  /// without reaching the player.
  final bool silencedChunk;

  /// The chunk arrived while the turn was held on a suspected interruption
  /// and was retained instead of played: it reaches the speaker if the hold
  /// resumes and is discarded if the interruption is committed.
  final bool heldChunk;
}

/// Feeds assistant audio to the player and decides what happens to audio left
/// over from a turn the user interrupted.
///
/// A finished turn keeps playing its queued tail so speech stays gapless, which
/// means the tail is still in the queue when the next answer starts arriving.
/// This class owns that overlap.
///
/// It also owns the difference between a suspected interruption and a
/// confirmed one. The platform player cannot pause — flushing it discards
/// whatever the native engine had scheduled — so every enqueued chunk is
/// retained here alongside the play window it was scheduled into. A suspected
/// interruption ([holdTurn]) silences the speaker instantly while keeping the
/// retained audio; sound that proves to be a keyboard rather than a voice is
/// taken back with [resumeHeldTurn], which re-enqueues the remainder from the
/// exact point the hold cut it.
final class ConversationPlaybackCoordinator {
  ConversationPlaybackCoordinator(this._player);

  final PcmAudioPlayer _player;

  static const int _bytesPerSecond =
      AudioConstants.sampleRateHz *
      AudioConstants.channelCount *
      AudioConstants.bitsPerSample ~/
      8;

  /// One sample frame; trims never split a 16-bit sample in half.
  static const int _bytesPerFrame =
      AudioConstants.channelCount * AudioConstants.bitsPerSample ~/ 8;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Chunks of the playing turn that the wall clock says have not finished
  /// coming out of the speaker, oldest first.
  final Queue<_RetainedChunk> _retained = Queue<_RetainedChunk>();
  DateTime _playheadUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _heldAt;
  bool _heldTurnWasFinished = false;
  bool _previousTurnPending = false;
  bool _turnInterrupted = false;

  /// True while playback is silenced for a suspected interruption whose
  /// audio is still retained and can come back.
  bool get isHolding => _heldAt != null;

  /// Marks the assistant's turn as finished while its queued tail keeps
  /// playing, so the next turn knows it has to clear that tail first.
  ///
  /// A turn the user cut off has no tail: its audio was flushed and its
  /// remaining chunks discarded, so the latch is simply released.
  void markTurnFinished() {
    if (_turnInterrupted) {
      _turnInterrupted = false;
      return;
    }
    if (_heldAt != null) {
      // The turn ended while its audio was held; whatever a resume brings
      // back is the tail of a finished turn.
      _heldTurnWasFinished = true;
      return;
    }
    _previousTurnPending = true;
  }

  /// Silences the turn on a suspected interruption while keeping its
  /// unplayed audio, so a false alarm — a keyboard, a knock — costs a beat
  /// of silence instead of the rest of the answer.
  ///
  /// Returns false when there is nothing audible to hold, a hold is already
  /// in place, or the turn was already cut for good.
  bool holdTurn() {
    if (_turnInterrupted || _heldAt != null) {
      return false;
    }
    final now = DateTime.now();
    _pruneRetained(now);
    if (_retained.isEmpty) {
      return false;
    }
    _heldAt = now;
    _heldTurnWasFinished = _previousTurnPending;
    _previousTurnPending = false;
    _player.flush();
    return true;
  }

  /// The suspicion proved to be noise: puts the held audio back on the
  /// player, trimmed to the point the hold silenced it, and returns the
  /// re-enqueued chunks so the caller can rebuild its playback model.
  ///
  /// The remainder stays retained afterwards, because the next keyboard
  /// click may hold the same turn again.
  List<Uint8List> resumeHeldTurn() {
    final heldAt = _heldAt;
    if (heldAt == null) {
      return const [];
    }
    _heldAt = null;
    if (_heldTurnWasFinished) {
      _previousTurnPending = true;
      _heldTurnWasFinished = false;
    }
    final chunks = List.of(_retained);
    _retained.clear();
    final resumed = <Uint8List>[];
    var start = DateTime.now();
    for (final chunk in chunks) {
      final bytes = chunk.start.isBefore(heldAt)
          ? _trimHeard(chunk, heldAt)
          : chunk.bytes;
      if (bytes.isEmpty) {
        continue;
      }
      final end = start.add(_durationOf(bytes));
      _retained.add(_RetainedChunk(bytes: bytes, start: start, end: end));
      start = end;
      if (_player.tryEnqueue(bytes)) {
        resumed.add(bytes);
      }
    }
    _playheadUntil = start;
    return resumed;
  }

  /// Cuts the assistant off the instant the user talks over it: whatever
  /// is queued, buffered or held is discarded, and every further chunk of
  /// the same turn is discarded until the turn officially ends.
  ///
  /// Returns false when there was already nothing left to silence, so the
  /// caller reacts to an interruption exactly once.
  bool interruptTurn() {
    if (_turnInterrupted) {
      return false;
    }
    if (_heldAt != null) {
      // The speaker was already silenced by the hold; committing decides
      // that the retained audio is never coming back.
      _heldAt = null;
      if (_heldTurnWasFinished) {
        _heldTurnWasFinished = false;
      } else {
        _turnInterrupted = true;
      }
      _discardRetained();
      return true;
    }
    if (_previousTurnPending) {
      // Only a finished turn's tail is playing; clearing it is enough and
      // must not latch, or it would swallow the answer that follows.
      _previousTurnPending = false;
    } else {
      _turnInterrupted = true;
    }
    _discardRetained();
    _player.flush();
    return true;
  }

  void reset() {
    _previousTurnPending = false;
    _turnInterrupted = false;
    _heldAt = null;
    _heldTurnWasFinished = false;
    _discardRetained();
  }

  PlaybackEnqueueResult enqueue(Uint8List bytes) {
    if (_turnInterrupted) {
      return const PlaybackEnqueueResult(
        flushedPreviousTurn: false,
        droppedChunk: false,
        silencedChunk: true,
      );
    }
    if (_heldAt != null) {
      if (!_heldTurnWasFinished) {
        _retainDuringHold(bytes);
        return const PlaybackEnqueueResult(
          flushedPreviousTurn: false,
          droppedChunk: false,
          heldChunk: true,
        );
      }
      // A new answer arriving over a held tail settles the suspicion: the
      // server heard the user too, so the tail is gone for good.
      _heldAt = null;
      _heldTurnWasFinished = false;
      _discardRetained();
      return PlaybackEnqueueResult(
        flushedPreviousTurn: true,
        droppedChunk: !_enqueueAndRetain(bytes),
      );
    }
    var flushedPreviousTurn = false;
    if (_previousTurnPending) {
      // A new answer supersedes whatever remained of the previous turn, which
      // is how the session recovers after the user interrupts the assistant.
      _previousTurnPending = false;
      _discardRetained();
      _player.flush();
      flushedPreviousTurn = true;
    }
    return PlaybackEnqueueResult(
      flushedPreviousTurn: flushedPreviousTurn,
      droppedChunk: !_enqueueAndRetain(bytes),
    );
  }

  bool _enqueueAndRetain(Uint8List bytes) {
    final now = DateTime.now();
    _pruneRetained(now);
    if (!_player.tryEnqueue(bytes)) {
      return false;
    }
    final start = _playheadUntil.isAfter(now) ? _playheadUntil : now;
    final end = start.add(_durationOf(bytes));
    _retained.add(_RetainedChunk(bytes: bytes, start: start, end: end));
    _playheadUntil = end;
    return true;
  }

  /// Chunks arriving during a hold are scheduled after whatever is already
  /// retained, so they land entirely on the unplayed side of the hold.
  void _retainDuringHold(Uint8List bytes) {
    final start = _retained.isEmpty ? DateTime.now() : _retained.last.end;
    _retained.add(
      _RetainedChunk(
        bytes: bytes,
        start: start,
        end: start.add(_durationOf(bytes)),
      ),
    );
  }

  /// Drops chunks the wall clock says the speaker has finished playing.
  ///
  /// A hold freezes pruning: the clock keeps running while the speaker is
  /// silent, and pruning against it would count silence as playback.
  void _pruneRetained(DateTime now) {
    if (_heldAt != null) {
      return;
    }
    while (_retained.isNotEmpty && !_retained.first.end.isAfter(now)) {
      _retained.removeFirst();
    }
  }

  void _discardRetained() {
    _retained.clear();
    _playheadUntil = _epoch;
  }

  /// Cuts off the part of [chunk] that had already been heard when the
  /// hold silenced the speaker, so a resume continues rather than repeats.
  Uint8List _trimHeard(_RetainedChunk chunk, DateTime heldAt) {
    final heardMicros = heldAt.difference(chunk.start).inMicroseconds;
    var offset =
        heardMicros * _bytesPerSecond ~/ Duration.microsecondsPerSecond;
    offset -= offset % _bytesPerFrame;
    if (offset <= 0) {
      return chunk.bytes;
    }
    if (offset >= chunk.bytes.length) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(chunk.bytes, offset);
  }

  static Duration _durationOf(Uint8List bytes) => Duration(
    microseconds:
        bytes.length * Duration.microsecondsPerSecond ~/ _bytesPerSecond,
  );
}

final class _RetainedChunk {
  const _RetainedChunk({
    required this.bytes,
    required this.start,
    required this.end,
  });

  final Uint8List bytes;
  final DateTime start;
  final DateTime end;
}
