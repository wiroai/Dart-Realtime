import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';

void main() {
  test('emits fixed 20 ms PCM chunks in FIFO order', () async {
    final source = FakePcmCaptureSource();
    final recorder = BufferedPcmAudioRecorder(source);
    addTearDown(recorder.dispose);
    final stream = await recorder.start(PcmCaptureProfile.transcription);
    final received = stream.take(2).toList();

    source.emit(
      Uint8List.fromList(
        List<int>.generate(
          AudioConstants.pcmBytesPerChunk * 2 + 80,
          (index) => index % 255,
        ),
      ),
    );

    final chunks = await received;
    expect(chunks, hasLength(2));
    expect(
      chunks.every(
        (chunk) => chunk.length == AudioConstants.pcmBytesPerChunk,
      ),
      isTrue,
    );
  });

  test('mute drops captured and already queued microphone audio', () async {
    final source = FakePcmCaptureSource();
    final recorder = BufferedPcmAudioRecorder(source);
    addTearDown(recorder.dispose);
    final stream = await recorder.start(PcmCaptureProfile.conversation);
    final received = stream.take(1).toList();

    recorder.setMuted(muted: true);
    source.emit(
      Uint8List(AudioConstants.pcmBytesPerChunk * 2),
    );
    recorder.setMuted(muted: false);
    source.emit(
      Uint8List.fromList(
        List<int>.filled(AudioConstants.pcmBytesPerChunk, 7),
      ),
    );

    final chunks = await received;
    expect(chunks, hasLength(1));
    expect(chunks.single.every((byte) => byte == 7), isTrue);
  });

  test('maps raw capture errors to a sanitized stream failure', () async {
    final source = FakePcmCaptureSource();
    final recorder = BufferedPcmAudioRecorder(source);
    addTearDown(recorder.dispose);
    final stream = await recorder.start(PcmCaptureProfile.transcription);
    final expectation = expectLater(
      stream,
      emitsError(isA<AudioCaptureFailure>()),
    );

    source.emitError(StateError('private platform detail'));

    await expectation;
  });

  test('repeated start stop and dispose release the source', () async {
    final source = FakePcmCaptureSource();
    final recorder = BufferedPcmAudioRecorder(source);

    await recorder.start(PcmCaptureProfile.transcription);
    await recorder.stop();
    await recorder.start(PcmCaptureProfile.conversation);
    await recorder.stop();
    await recorder.dispose();
    await recorder.dispose();

    expect(source.startCalls, 2);
    expect(source.stopCalls, 2);
    expect(source.disposeCalls, 1);
  });
}

final class FakePcmCaptureSource implements PcmCaptureSource {
  StreamController<Uint8List>? _controller;

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<Stream<Uint8List>> start(PcmCaptureProfile profile) async {
    startCalls++;
    _recording = true;
    _controller = StreamController<Uint8List>(sync: true);
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    if (!_recording) {
      return;
    }
    stopCalls++;
    _recording = false;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await stop();
  }

  void emit(Uint8List bytes) {
    _controller?.add(bytes);
  }

  void emitError(Object error) {
    _controller?.addError(error);
  }
}
