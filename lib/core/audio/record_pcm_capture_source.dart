import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';

final class RecordPcmCaptureSource implements PcmCaptureSource {
  RecordPcmCaptureSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _recording = false;
  bool _disposed = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<Stream<Uint8List>> start(PcmCaptureProfile profile) async {
    if (_disposed) {
      throw StateError('The PCM capture source is disposed.');
    }
    await _recorder.ios?.manageAudioSession(false);
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AudioConstants.sampleRateHz,
        numChannels: AudioConstants.channelCount,
        autoGain: true,
        echoCancel: profile == PcmCaptureProfile.conversation,
        noiseSuppress: true,
        streamBufferSize: AudioConstants.pcmBytesPerChunk * 4,
      ),
    );
    _recording = true;
    return stream;
  }

  @override
  Future<void> stop() async {
    if (!_recording) {
      return;
    }
    _recording = false;
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _recording = false;
    await _recorder.dispose();
  }
}
