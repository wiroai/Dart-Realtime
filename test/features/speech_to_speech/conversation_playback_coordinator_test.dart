import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_playback_coordinator.dart';

void main() {
  late _FakePcmAudioPlayer player;
  late ConversationPlaybackCoordinator coordinator;

  setUp(() {
    player = _FakePcmAudioPlayer();
    coordinator = ConversationPlaybackCoordinator(player);
  });

  test('audio inside one turn reaches the player untouched', () {
    final first = coordinator.enqueue(_chunk(1));
    final second = coordinator.enqueue(_chunk(2));

    expect(player.flushes, isZero);
    expect(player.enqueued, [_chunk(1), _chunk(2)]);
    expect(first.flushedPreviousTurn, isFalse);
    expect(second.flushedPreviousTurn, isFalse);
  });

  test('the first chunk of a new turn clears the interrupted tail', () {
    coordinator
      ..enqueue(_chunk(1))
      ..markTurnFinished();

    final outcome = coordinator.enqueue(_chunk(2));

    expect(outcome.flushedPreviousTurn, isTrue);
    expect(player.flushes, 1);
    expect(player.enqueued, [_chunk(1), _chunk(2)]);
  });

  test('only the first chunk of a new turn flushes', () {
    coordinator.markTurnFinished();

    final second = (coordinator..enqueue(_chunk(1))).enqueue(_chunk(2));

    expect(player.flushes, 1);
    expect(second.flushedPreviousTurn, isFalse);
  });

  test('a full queue is reported as a dropped chunk', () {
    player.accepts = false;

    final outcome = coordinator.enqueue(_chunk(1));

    expect(outcome.droppedChunk, isTrue);
    expect(outcome.flushedPreviousTurn, isFalse);
  });

  test('a flush and a drop are reported together', () {
    coordinator.markTurnFinished();
    player.accepts = false;

    final outcome = coordinator.enqueue(_chunk(1));

    expect(outcome.flushedPreviousTurn, isTrue);
    expect(outcome.droppedChunk, isTrue);
    expect(player.flushes, 1);
  });

  test('reset drops the pending turn so a new session never flushes', () {
    coordinator
      ..markTurnFinished()
      ..reset();

    final outcome = coordinator.enqueue(_chunk(1));

    expect(outcome.flushedPreviousTurn, isFalse);
    expect(player.flushes, isZero);
  });
}

Uint8List _chunk(int seed) => Uint8List.fromList([seed, seed]);

final class _FakePcmAudioPlayer implements PcmAudioPlayer {
  bool accepts = true;
  int flushes = 0;
  List<Uint8List> enqueued = [];

  @override
  bool tryEnqueue(Uint8List chunk) {
    if (!accepts) {
      return false;
    }
    enqueued.add(chunk);
    return true;
  }

  @override
  void flush() => flushes++;

  @override
  bool get isPlaying => true;

  @override
  bool get isEnabled => true;

  @override
  Stream<AudioPlaybackFailure> get failures => const Stream.empty();

  @override
  int get droppedChunks => 0;

  @override
  int get queueHighWaterMarkInChunks => 0;

  @override
  int get maximumFeedLatencyMicros => 0;

  @override
  int get underrunCount => 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> enqueue(Uint8List chunk) async {}

  @override
  Future<void> complete() async {}

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
