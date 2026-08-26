import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/pcm_level_meter.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_mic_pipeline.dart';

void main() {
  test('without a gate the chunk is measured and passed through', () {
    final pipeline = ConversationMicPipeline(onStall: () {});
    addTearDown(pipeline.dispose);
    final chunk = _pcm(amplitude: 15000);

    final processed = pipeline.process(chunk, assistantAudible: false);

    expect(processed.gated, same(chunk));
    expect(processed.level, pcmNormalizedLevel(chunk));
  });

  test('with a gate the measured level is the gated output', () {
    final gate = PcmNoiseGate();
    final pipeline = ConversationMicPipeline(
      onStall: () {},
      noiseGate: gate,
    );
    addTearDown(pipeline.dispose);
    final chunk = _pcm(amplitude: 300);

    final processed = pipeline.process(chunk, assistantAudible: false);

    expect(processed.gated, isNot(same(chunk)));
    expect(processed.level, gate.lastOutputLevel);
    expect(processed.level, lessThan(pcmNormalizedLevel(chunk)));
  });

  test('the watchdog fires after silence', () async {
    var stalls = 0;
    final pipeline = ConversationMicPipeline(
      onStall: () => stalls++,
      stallTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(pipeline.dispose);

    pipeline.startWatchdog();
    expect(stalls, 0);

    // Tick is floored at 100 ms, so the first check is past the timeout.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(stalls, 1);
  });

  test('the watchdog stays quiet while chunks flow', () async {
    var stalls = 0;
    final pipeline = ConversationMicPipeline(
      onStall: () => stalls++,
      stallTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(pipeline.dispose);

    pipeline.startWatchdog();
    for (var tick = 0; tick < 8; tick++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      pipeline.process(_pcm(amplitude: 0), assistantAudible: false);
    }

    expect(stalls, 0);
  });
}

Uint8List _pcm({required int amplitude, int samples = 480}) {
  final data = ByteData(samples * 2);
  for (var index = 0; index < samples; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}
