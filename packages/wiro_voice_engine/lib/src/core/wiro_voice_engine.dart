import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'audio_config.dart';
import 'audio_session_config.dart';

/// Dart side of the shared native audio graph.
///
/// Capture and playback run inside one native engine so the platform's
/// acoustic echo cancellation can subtract speaker output from what the
/// microphone hears — the requirement that makes this bridge exist.
class WiroVoiceEngine {
  static const MethodChannel _channel = MethodChannel('wiro_voice_engine');
  static const EventChannel _eventChannel =
      EventChannel('wiro_voice_engine/events');

  AudioConfig audioConfig = AudioConfig();
  AudioSessionConfig sessionConfig = AudioSessionConfig();
  bool isInitialized = false;
  bool isRecording = false;

  final _audioChunkController = StreamController<Uint8List>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  WiroVoiceEngine() {
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) {
          _errorController.add('Invalid event data type: ${event.runtimeType}');
          return;
        }
        final type = event['type'] as String?;
        switch (type) {
          case 'audio_chunk':
            final data = event['data'];
            if (data is Uint8List) {
              _audioChunkController.add(data);
            } else {
              _errorController
                  .add('Invalid audio chunk data type: ${data.runtimeType}');
            }
          case 'error':
            final message = event['message'] as String?;
            if (message != null) {
              _errorController.add(message);
            }
          default:
            _errorController.add('Unknown event type: $type');
        }
      },
      onError: (Object e) => _errorController.add('Event stream error: $e'),
      onDone: () => _errorController.add('Event stream closed'),
    );
  }

  /// Microphone chunks in the wire format (16-bit little-endian PCM).
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  Stream<String> get errorStream => _errorController.stream;

  Future<void> initialize() async {
    await _channel.invokeMethod('initialize', {
      'audioConfig': audioConfig.toMap(),
      'sessionConfig': sessionConfig.toMap(),
    });
    isInitialized = true;
  }

  Future<void> startRecording() async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('startRecording');
    isRecording = true;
  }

  Future<void> stopRecording() async {
    if (!isInitialized || !isRecording) return;
    await _channel.invokeMethod('stopRecording');
    isRecording = false;
  }

  Future<void> playAudioChunk(Uint8List data) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('playAudioChunk', {'audioData': data});
  }

  Future<void> stopPlayback() async {
    if (!isInitialized) return;
    await _channel.invokeMethod('stopPlayback');
  }

  Future<void> shutdownAll() async {
    if (!isInitialized) return;
    await _channel.invokeMethod('shutdownAll');
    isInitialized = false;
    isRecording = false;
    await _audioChunkController.close();
    await _errorController.close();
  }
}
