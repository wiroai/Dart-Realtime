import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';

/// What happened to a chunk of assistant audio on its way to the speaker.
///
/// The two outcomes are independent: a chunk can clear an interrupted turn and
/// still be dropped by a full queue.
final class PlaybackEnqueueResult {
  const PlaybackEnqueueResult({
    required this.flushedPreviousTurn,
    required this.droppedChunk,
  });

  final bool flushedPreviousTurn;
  final bool droppedChunk;
}

/// Feeds assistant audio to the player and decides what happens to audio left
/// over from a turn the user interrupted.
///
/// A finished turn keeps playing its queued tail so speech stays gapless, which
/// means the tail is still in the queue when the next answer starts arriving.
/// This class owns that overlap.
final class ConversationPlaybackCoordinator {
  ConversationPlaybackCoordinator(this._player);

  final PcmAudioPlayer _player;

  bool _previousTurnPending = false;

  /// Marks the assistant's turn as finished while its queued tail keeps
  /// playing, so the next turn knows it has to clear that tail first.
  void markTurnFinished() {
    _previousTurnPending = true;
  }

  void reset() {
    _previousTurnPending = false;
  }

  PlaybackEnqueueResult enqueue(Uint8List bytes) {
    var flushedPreviousTurn = false;
    if (_previousTurnPending) {
      // A new answer supersedes whatever remained of the previous turn, which
      // is how the session recovers after the user interrupts the assistant.
      _previousTurnPending = false;
      _player.flush();
      flushedPreviousTurn = true;
    }
    return PlaybackEnqueueResult(
      flushedPreviousTurn: flushedPreviousTurn,
      droppedChunk: !_player.tryEnqueue(bytes),
    );
  }
}
