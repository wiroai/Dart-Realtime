import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_barge_in.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_playback_coordinator.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';

void main() {
  late _FakePcmAudioPlayer player;
  late ConversationPlaybackCoordinator playback;
  late ConversationVoiceActivity voiceActivity;
  late List<String> protocolEvents;
  late ConversationBargeIn bargeIn;

  setUp(() {
    player = _FakePcmAudioPlayer();
    playback = ConversationPlaybackCoordinator(player);
    voiceActivity = ConversationVoiceActivity();
    protocolEvents = <String>[];
    bargeIn = ConversationBargeIn(
      playback: playback,
      voiceActivity: voiceActivity,
      onProtocolEvent: protocolEvents.add,
      holdTimeout: const Duration(milliseconds: 900),
      holdCooldown: const Duration(milliseconds: 1500),
    );
    addTearDown(() {
      bargeIn.dispose();
      voiceActivity.dispose();
    });
  });

  test('suspect speech holds playback without committing', () {
    _queueAssistantAudio(playback, voiceActivity);

    _feedLoudUserChunks(voiceActivity, bargeIn, count: 3);

    expect(player.flushes, 1);
    expect(playback.isHolding, isTrue);
    expect(protocolEvents, ['assistant_playback_held']);
  });

  test('drained evidence resumes the held turn and starts cooldown', () {
    _queueAssistantAudio(playback, voiceActivity);
    _feedLoudUserChunks(voiceActivity, bargeIn, count: 3);

    for (var index = 0; index < 3; index++) {
      voiceActivity.addUserChunk(_pcm(amplitude: 0));
      bargeIn.evaluate();
    }

    expect(playback.isHolding, isFalse);
    expect(protocolEvents, [
      'assistant_playback_held',
      'assistant_playback_resumed',
    ]);
    expect(player.enqueued, isNotEmpty);
  });

  test('sustained speech commits the interruption', () {
    _queueAssistantAudio(playback, voiceActivity);

    _feedLoudUserChunks(voiceActivity, bargeIn, count: 8);

    expect(playback.isHolding, isFalse);
    expect(protocolEvents, [
      'assistant_playback_held',
      'assistant_interrupted',
    ]);
  });

  test('hold deadline expiry resumes without a commit', () {
    fakeAsync((async) {
      _queueAssistantAudio(playback, voiceActivity);
      _feedLoudUserChunks(voiceActivity, bargeIn, count: 3);

      expect(protocolEvents, ['assistant_playback_held']);

      // Leave the streak above zero so only the deadline can resolve the
      // hold — quiet chunks would resume through evaluate() instead.
      async.elapse(const Duration(milliseconds: 900));

      expect(playback.isHolding, isFalse);
      expect(protocolEvents, [
        'assistant_playback_held',
        'assistant_playback_resumed',
      ]);
    });
  });

  test('cooldown suppresses new holds but not confirmed interrupts', () {
    fakeAsync((async) {
      _queueAssistantAudio(playback, voiceActivity);
      _feedLoudUserChunks(voiceActivity, bargeIn, count: 3);
      for (var index = 0; index < 3; index++) {
        voiceActivity.addUserChunk(_pcm(amplitude: 0));
        bargeIn.evaluate();
      }
      expect(protocolEvents.last, 'assistant_playback_resumed');

      // Rebuild a long assistant playhead after the resume reset Ai.
      _queueAssistantAudio(playback, voiceActivity);

      // Still inside the cooldown: three loud chunks would otherwise hold.
      _feedLoudUserChunks(voiceActivity, bargeIn, count: 3);
      expect(playback.isHolding, isFalse);
      expect(
        protocolEvents.where((e) => e == 'assistant_playback_held'),
        hasLength(1),
      );

      // Sustained speech still cuts through during the rest.
      _feedLoudUserChunks(voiceActivity, bargeIn, count: 5);
      expect(protocolEvents, contains('assistant_interrupted'));
    });
  });
}

void _queueAssistantAudio(
  ConversationPlaybackCoordinator playback,
  ConversationVoiceActivity voiceActivity,
) {
  // One second of audio keeps the playhead ahead for the whole case.
  final chunk = _pcm(amplitude: 8000, milliseconds: 1000);
  playback.enqueue(chunk);
  voiceActivity.addAiChunk(chunk);
}

void _feedLoudUserChunks(
  ConversationVoiceActivity voiceActivity,
  ConversationBargeIn bargeIn, {
  required int count,
}) {
  for (var index = 0; index < count; index++) {
    voiceActivity.addUserChunk(_pcm(amplitude: 20000));
    bargeIn.evaluate();
  }
}

/// Constant-amplitude 16-bit little-endian PCM at the wire format's
/// 24 kHz mono layout.
Uint8List _pcm({required int amplitude, int milliseconds = 20}) {
  final sampleCount = 24000 * milliseconds ~/ 1000;
  final data = ByteData(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

final class _FakePcmAudioPlayer implements PcmAudioPlayer {
  final List<Uint8List> enqueued = [];
  int flushes = 0;

  @override
  bool tryEnqueue(Uint8List chunk) {
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
