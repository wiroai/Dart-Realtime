import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';

void main() {
  late ConversationVoiceActivity activity;

  setUp(() {
    activity = ConversationVoiceActivity();
    addTearDown(activity.dispose);
  });

  test('assistant audio owns the phase until the playhead passes', () {
    activity.addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000));

    expect(activity.phase, ConversationVoicePhase.aiSpeaking);
    expect(activity.aiLevel, greaterThan(0));

    activity.resetAi();

    expect(activity.phase, ConversationVoicePhase.quiet);
    expect(activity.aiLevel, 0);
  });

  test('a loud user takes the floor from a talking assistant', () {
    activity
      ..addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000))
      ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));

    expect(activity.phase, ConversationVoicePhase.userSpeaking);
  });

  test('a burst of loud chunks raises suspicion before confirmation', () {
    // Two loud chunks are forty milliseconds: not yet even a suspicion.
    activity
      ..addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000))
      ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20))
      ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));

    expect(activity.userMaybeInterrupting, isFalse);

    activity.addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));

    expect(activity.userMaybeInterrupting, isTrue);
    expect(activity.userInterrupting, isFalse);

    activity.resetAi();

    expect(activity.userMaybeInterrupting, isFalse);
  });

  test('sustained loud speech confirms the interruption', () {
    activity.addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000));

    for (var index = 0; index < 8; index++) {
      activity.addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));
    }

    expect(activity.userInterrupting, isTrue);

    activity.resetAi();

    expect(activity.userInterrupting, isFalse);
  });

  test('natural speech with brief dips still confirms', () {
    activity.addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000));

    // Three loud chunks then one dip, the cadence of real syllables: the
    // leaky counter climbs two steps per cycle and reaches the target.
    for (var cycle = 0; cycle < 5; cycle++) {
      activity
        ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20))
        ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20))
        ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20))
        ..addUserChunk(_pcm(amplitude: 0, milliseconds: 20));
    }
    activity.addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));

    expect(activity.userInterrupting, isTrue);
  });

  test('keyboard-like clicks never confirm and their evidence drains', () {
    activity.addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000));

    // Two loud chunks then a longer gap, the cadence of typing: the leaky
    // counter drains in each gap and never approaches the confirm target.
    for (var click = 0; click < 6; click++) {
      activity
        ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20))
        ..addUserChunk(_pcm(amplitude: 20000, milliseconds: 20));
      for (var gap = 0; gap < 5; gap++) {
        activity.addUserChunk(_pcm(amplitude: 0, milliseconds: 20));
      }
    }

    expect(activity.userInterrupting, isFalse);
    expect(activity.hasInterruptEvidence, isFalse);
  });

  test('quiet speech never counts as an interruption', () {
    activity.addAiChunk(_pcm(amplitude: 8000, milliseconds: 2000));

    for (var index = 0; index < 10; index++) {
      activity.addUserChunk(_pcm(amplitude: 900, milliseconds: 20));
    }

    expect(activity.userInterrupting, isFalse);
    expect(activity.phase, ConversationVoicePhase.aiSpeaking);
  });
}

/// Constant-amplitude 16-bit little-endian PCM at the wire format's
/// 24 kHz mono layout.
Uint8List _pcm({required int amplitude, required int milliseconds}) {
  final sampleCount = 24000 * milliseconds ~/ 1000;
  final data = ByteData(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}
