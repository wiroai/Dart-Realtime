import 'dart:math' as math;
import 'dart:typed_data';

/// Perceptual loudness of one 16-bit little-endian PCM chunk, 0..1.
///
/// RMS is mapped through a power curve so normal speech spans most of the
/// range instead of huddling near zero; every consumer of microphone or
/// assistant levels must read the same scale, which is why this lives in
/// one place.
double pcmNormalizedLevel(Uint8List chunk) {
  final sampleCount = chunk.length ~/ 2;
  if (sampleCount == 0) {
    return 0;
  }
  final data = ByteData.sublistView(chunk);
  var sumOfSquares = 0.0;
  for (var index = 0; index < sampleCount; index++) {
    final sample = data.getInt16(index * 2, Endian.little) / 32768;
    sumOfSquares += sample * sample;
  }
  final rms = math.sqrt(sumOfSquares / sampleCount);
  return math.min(1, math.pow(rms * 5, 0.8).toDouble());
}
