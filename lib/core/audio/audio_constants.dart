/// PCM wire format from Wiro realtime docs, verified 2026-08-21.
///
/// Samples are signed 16-bit little-endian on both directions of the
/// stream; changing the rate means changing it in the Run request and in
/// the local pipeline together, or the audio is garbled.
abstract final class AudioConstants {
  static const int sampleRateHz = 24000;
  static const int channelCount = 1;
  static const int bitsPerSample = 16;
  static const Duration chunkDuration = Duration(milliseconds: 20);
  static const int samplesPerChunk = 480;
  static const int pcmBytesPerChunk = 960;
}
