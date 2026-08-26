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

  test('interrupting flushes once and silences the rest of the turn', () {
    coordinator.enqueue(_chunk(1));

    expect(coordinator.interruptTurn(), isTrue);
    expect(coordinator.interruptTurn(), isFalse);

    final silenced = coordinator.enqueue(_chunk(2));

    expect(player.flushes, 1);
    expect(silenced.silencedChunk, isTrue);
    expect(player.enqueued, [_chunk(1)]);
  });

  test('the turn after an interruption plays normally', () {
    coordinator
      ..enqueue(_chunk(1))
      ..interruptTurn()
      ..enqueue(_chunk(2))
      ..markTurnFinished();

    final outcome = coordinator.enqueue(_chunk(3));

    expect(outcome.silencedChunk, isFalse);
    expect(outcome.flushedPreviousTurn, isFalse);
    expect(player.enqueued, [_chunk(1), _chunk(3)]);
  });

  test('interrupting a finished tail clears it without latching', () {
    coordinator
      ..enqueue(_chunk(1))
      ..markTurnFinished();

    expect(coordinator.interruptTurn(), isTrue);

    final outcome = coordinator.enqueue(_chunk(2));

    expect(outcome.silencedChunk, isFalse);
    expect(outcome.flushedPreviousTurn, isFalse);
    expect(player.flushes, 1);
    expect(player.enqueued, [_chunk(1), _chunk(2)]);
  });

  test('a hold silences the player but keeps the turn resumable', () {
    coordinator.enqueue(_secondLong(1));

    expect(coordinator.holdTurn(), isTrue);
    expect(coordinator.isHolding, isTrue);
    expect(player.flushes, 1);

    final resumed = coordinator.resumeHeldTurn();

    expect(coordinator.isHolding, isFalse);
    expect(resumed, hasLength(1));
    // The heard head is trimmed away, so the resume continues instead of
    // repeating; nearly the whole second is still unheard.
    expect(resumed.single.length, lessThanOrEqualTo(48000));
    expect(resumed.single.length, greaterThan(40000));
    expect(player.enqueued, hasLength(2));
  });

  test('chunks arriving during a hold play only after the resume', () {
    coordinator
      ..enqueue(_secondLong(1))
      ..holdTurn();

    final held = coordinator.enqueue(_secondLong(2));

    expect(held.heldChunk, isTrue);
    expect(player.enqueued, hasLength(1));

    final resumed = coordinator.resumeHeldTurn();

    expect(resumed, hasLength(2));
    expect(player.enqueued, hasLength(3));
  });

  test('committing a held turn discards its audio and latches', () {
    coordinator
      ..enqueue(_secondLong(1))
      ..holdTurn();

    expect(coordinator.interruptTurn(), isTrue);
    expect(coordinator.resumeHeldTurn(), isEmpty);

    final silenced = coordinator.enqueue(_secondLong(2));

    expect(silenced.silencedChunk, isTrue);
    expect(player.enqueued, hasLength(1));
  });

  test('holding with nothing unplayed is refused', () {
    expect(coordinator.holdTurn(), isFalse);
    expect(player.flushes, isZero);
  });

  test('a hold across the turn boundary resumes as a finished tail', () {
    coordinator
      ..enqueue(_secondLong(1))
      ..holdTurn()
      ..markTurnFinished()
      ..resumeHeldTurn();

    final outcome = coordinator.enqueue(_secondLong(2));

    expect(outcome.flushedPreviousTurn, isTrue);
  });

  test('a new answer over a held finished tail supersedes it', () {
    coordinator
      ..enqueue(_secondLong(1))
      ..markTurnFinished()
      ..holdTurn();

    final outcome = coordinator.enqueue(_secondLong(2));

    expect(outcome.heldChunk, isFalse);
    expect(outcome.flushedPreviousTurn, isTrue);
    expect(coordinator.isHolding, isFalse);
    expect(player.enqueued.last, _secondLong(2));
  });

  test('reset clears a hold so nothing from it ever resumes', () {
    coordinator
      ..enqueue(_secondLong(1))
      ..holdTurn()
      ..reset();

    expect(coordinator.isHolding, isFalse);
    expect(coordinator.resumeHeldTurn(), isEmpty);
  });
}

Uint8List _chunk(int seed) => Uint8List.fromList([seed, seed]);

/// One second of audio at the 24 kHz 16-bit mono wire format, so the
/// wall-clock playhead cannot outrun the chunk within a test.
Uint8List _secondLong(int seed) => Uint8List(48000)..fillRange(0, 48000, seed);

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
