import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';

/// One 16-bit little-endian PCM chunk at a constant amplitude.
Uint8List _pcm({required int amplitude, int samples = 480}) {
  final data = ByteData(samples * 2);
  for (var index = 0; index < samples; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

int _maxAmplitude(Uint8List chunk) {
  final data = ByteData.sublistView(chunk);
  var max = 0;
  for (var offset = 0; offset + 1 < chunk.length; offset += 2) {
    final sample = data.getInt16(offset, Endian.little).abs();
    if (sample > max) {
      max = sample;
    }
  }
  return max;
}

void main() {
  test('quiet room audio is attenuated to a whisper, never zeroed', () {
    final gate = PcmNoiseGate();

    final output = gate.process(_pcm(amplitude: 300));

    expect(gate.isOpen, isFalse);
    expect(_maxAmplitude(output), lessThan(30));
    // The stream must stay audibly alive: a long quiet spell of pure
    // digital zeros can get the task reaped server-side.
    expect(_maxAmplitude(output), greaterThan(0));
  });

  test('near-field speech opens the gate and passes untouched', () {
    final gate = PcmNoiseGate();
    final input = _pcm(amplitude: 15000);

    final output = gate.process(input);

    expect(output, input);
    expect(gate.isOpen, isTrue);
  });

  test('the dip between two words stays inside the hangover', () {
    final gate = PcmNoiseGate()..process(_pcm(amplitude: 15000));
    // The tail of a word: under the bar that opens the gate, well over
    // the room it was opened in.
    final dip = _pcm(amplitude: 900);

    final output = gate.process(dip);

    expect(output, dip);
  });

  // Without a bar of its own the hangover is a hole in the gate: one
  // knock, one door slam, one cough opens it and the room walks through
  // for the next half second — which the server hears as the user
  // starting to talk.
  test('the hangover lowers the bar without removing it', () {
    final gate = PcmNoiseGate()..process(_pcm(amplitude: 15000));

    final hum = gate.process(_pcm(amplitude: 200));

    expect(_maxAmplitude(hum), lessThan(30));
  });

  // An air conditioner is loud enough to open the gate and never stops,
  // so the slow creep meant for a television cannot learn it: every dip
  // pulls the floor back down faster than the creep raised it. What
  // gives it away is not its volume but that it never moves.
  test('a steady hum is recognised and learned in seconds', () {
    // The hangover is a wall-clock window this test cannot wait out; it
    // is what the case above is for.
    final gate = PcmNoiseGate(hangover: Duration.zero);
    final hum = _pcm(amplitude: 1500);

    // It gets in at first: one chunk of anything looks like a hum.
    expect(gate.process(hum), hum);
    expect(gate.hearsHum, isFalse);

    // A second of it at fifty chunks a second is enough to name it.
    for (var index = 0; index < 50; index++) {
      gate.process(hum);
    }
    expect(gate.hearsHum, isTrue);

    for (var index = 0; index < 150; index++) {
      gate.process(hum);
    }
    expect(_maxAmplitude(gate.process(hum)), lessThan(150));

    // And the person in the room is still heard over it.
    final speech = _pcm(amplitude: 15000);
    expect(gate.process(speech), speech);
  });

  // Flatness is the whole basis of the hum test, so speech — which is
  // never flat, because syllables arrive four to eight a second — must
  // never trip it, however long someone talks.
  test('a long sentence is never mistaken for a machine', () {
    final gate = PcmNoiseGate();
    const syllables = [14000, 16000, 9000, 15000, 6000, 13000, 800, 11000];

    // Ten seconds of talking.
    for (var index = 0; index < 500; index++) {
      gate.process(_pcm(amplitude: syllables[index % syllables.length]));
      expect(gate.hearsHum, isFalse, reason: 'chunk $index');
    }

    final loud = _pcm(amplitude: 15000);
    expect(gate.process(loud), loud);
  });

  // A hum does not stop being a hum because it is loud, and speech does
  // not become one because it is quiet: the test reads the spread
  // relative to the level, never the level.
  test('the hum test reads shape, not volume', () {
    final loudHum = PcmNoiseGate(hangover: Duration.zero);
    final quietSpeech = PcmNoiseGate(hangover: Duration.zero);
    const syllables = [1400, 1600, 900, 1500, 600, 1300, 80, 1100];

    for (var index = 0; index < 100; index++) {
      loudHum.process(_pcm(amplitude: 14000));
      quietSpeech.process(_pcm(amplitude: syllables[index % 8]));
    }

    expect(loudHum.hearsHum, isTrue);
    expect(quietSpeech.hearsHum, isFalse);
  });

  test('a television becomes the learned floor and stays attenuated', () {
    final gate = PcmNoiseGate(hangover: Duration.zero);

    // Under a minute of steady television teaches the gate the room.
    for (var index = 0; index < 2000; index++) {
      gate.process(_pcm(amplitude: 2500));
    }

    expect(gate.ambientFloor, greaterThan(0.1));
    final television = gate.process(_pcm(amplitude: 2500));
    expect(_maxAmplitude(television), lessThan(200));

    // The user still cuts through, because near-field speech rises far
    // above what the room taught the gate.
    final speechInput = _pcm(amplitude: 18000);
    expect(gate.process(speechInput), speechInput);
  });

  test('assistant playback raises the bar so echo stays attenuated', () {
    final gate = PcmNoiseGate();
    // Speaker bleed at a level that would open the gate in a quiet room.
    final echo = _pcm(amplitude: 2000);

    final leaked = gate.process(echo, assistantAudible: true);

    expect(gate.isOpen, isFalse);
    expect(_maxAmplitude(leaked), lessThan(200));

    // The user genuinely talking over the assistant still cuts through,
    // exactly like the barge-in threshold.
    final speech = _pcm(amplitude: 15000);
    expect(gate.process(speech, assistantAudible: true), speech);
    expect(gate.isOpen, isTrue);
  });

  test('reset forgets the learned room', () {
    final gate = PcmNoiseGate();
    for (var index = 0; index < 2000; index++) {
      gate.process(_pcm(amplitude: 2500));
    }
    expect(gate.ambientFloor, greaterThan(0.1));

    gate.reset();

    expect(gate.ambientFloor, 0);
    expect(gate.isOpen, isFalse);
  });
}
