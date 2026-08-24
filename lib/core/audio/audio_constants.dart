/// PCM wire format from Wiro realtime docs, verified 2026-08-21.
///
/// Endianness is not stated in MCP docs. This example treats samples as
/// little-endian until a physical-device test confirms the stream.
abstract final class AudioConstants {
  static const int sampleRateHz = 24000;
  static const int channelCount = 1;
  static const int bitsPerSample = 16;
  static const Duration chunkDuration = Duration(milliseconds: 20);
  static const int samplesPerChunk = 480;
  static const int pcmBytesPerChunk = 960;
}
