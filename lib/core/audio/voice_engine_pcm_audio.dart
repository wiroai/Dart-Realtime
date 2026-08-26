import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_voice_engine/wiro_voice_engine.dart';

/// Conversation adapters sharing one native input/output graph.
///
/// The shared graph is required for native acoustic echo cancellation to
/// correlate speaker output with microphone input.
final class VoiceEnginePcmAudioPair {
  VoiceEnginePcmAudioPair() {
    final coordinator = _VoiceEngineCoordinator();
    recorder = BufferedPcmAudioRecorder(
      _VoiceEngineCaptureSource(coordinator),
    );
    player = QueuedPcmAudioPlayer(
      _VoiceEnginePlaybackSink(coordinator),
    );
  }

  late final PcmAudioRecorder recorder;
  late final PcmAudioPlayer player;
}

final class _VoiceEngineCoordinator {
  final StreamController<Uint8List> _captureController =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<String> _errorController =
      StreamController<String>.broadcast(sync: true);

  WiroVoiceEngine? _engine;
  StreamSubscription<Uint8List>? _captureSubscription;
  StreamSubscription<String>? _errorSubscription;
  Future<void>? _initialization;
  bool _disposed = false;
  bool isRecording = false;

  Stream<Uint8List> get capture => _captureController.stream;

  Stream<String> get errors => _errorController.stream;

  Future<void> initialize() async {
    if (_disposed) {
      throw const AudioCaptureFailure();
    }
    if (_engine?.isInitialized ?? false) {
      return;
    }

    final pending = _initialization;
    if (pending != null) {
      await pending;
      return;
    }

    final operation = _initialize();
    _initialization = operation;
    try {
      await operation;
    } finally {
      if (identical(_initialization, operation)) {
        _initialization = null;
      }
    }
  }

  Future<void> startRecording() async {
    await initialize();
    if (isRecording) {
      return;
    }
    await _engine?.startRecording();
    isRecording = true;
  }

  Future<void> stopRecording() async {
    if (!isRecording) {
      return;
    }
    isRecording = false;
    await _engine?.stopRecording();
  }

  Future<void> play(Uint8List chunk) async {
    await _engine?.playAudioChunk(chunk);
  }

  Future<void> stopPlayback() async {
    await _engine?.stopPlayback();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    isRecording = false;
    await _captureSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _engine?.shutdownAll();
    _engine = null;
    await _captureController.close();
    await _errorController.close();
  }

  Future<void> _initialize() async {
    final engine = WiroVoiceEngine()
      ..audioConfig = AudioConfig(
        bufferSize: AudioConstants.pcmBytesPerChunk,
        amplitudeThreshold: 0,
      )
      ..sessionConfig = _VoiceChatAudioSessionConfig(
        preferredBufferDuration:
            AudioConstants.chunkDuration.inMicroseconds /
            Duration.microsecondsPerSecond,
      );
    _engine = engine;
    _captureSubscription = engine.audioChunkStream.listen(
      _handleCapture,
      onError: _handleError,
    );
    _errorSubscription = engine.errorStream.listen(_handleError);
    await engine.initialize();
  }

  void _handleCapture(Uint8List chunk) {
    if (isRecording && !_captureController.isClosed) {
      _captureController.add(chunk);
    }
  }

  void _handleError(Object error) {
    if (!_errorController.isClosed) {
      _errorController.add(error.toString());
    }
  }
}

final class _VoiceChatAudioSessionConfig extends AudioSessionConfig {
  _VoiceChatAudioSessionConfig({
    required super.preferredBufferDuration,
  }) : super(
         mode: AudioMode.voiceChat,
         options: const {
           AudioOption.allowBluetooth,
           AudioOption.defaultToSpeaker,
         },
       );

  @override
  Map<String, dynamic> toMap() => {
    'category': 'playAndRecord',
    'mode': 'voiceChat',
    'options': [
      'allowBluetooth',
      'defaultToSpeaker',
    ],
    'preferredBufferDuration': preferredBufferDuration,
  };
}

final class _VoiceEngineCaptureSource implements PcmCaptureSource {
  _VoiceEngineCaptureSource(this._coordinator);

  final _VoiceEngineCoordinator _coordinator;

  @override
  bool get isRecording => _coordinator.isRecording;

  @override
  Future<Stream<Uint8List>> start(PcmCaptureProfile profile) async {
    await _coordinator.startRecording();
    return _coordinator.capture;
  }

  @override
  Future<void> stop() => _coordinator.stopRecording();

  @override
  Future<void> dispose() => _coordinator.dispose();
}

final class _VoiceEnginePlaybackSink implements PcmPlaybackSink {
  _VoiceEnginePlaybackSink(this._coordinator);

  final _VoiceEngineCoordinator _coordinator;

  @override
  Stream<void> get underruns => const Stream<void>.empty();

  @override
  Future<void> initialize() => _coordinator.initialize();

  @override
  Future<void> play() async {}

  @override
  Future<void> feed(Uint8List chunk) => _coordinator.play(chunk);

  @override
  Future<void> flush() => _coordinator.stopPlayback();

  @override
  Future<Duration> bufferedDuration() async => Duration.zero;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> endOfStream() async {}

  @override
  Future<void> stop() => _coordinator.stopPlayback();

  @override
  Future<void> dispose() => _coordinator.dispose();
}
