import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_metrics.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/speech_to_speech_session_service.dart';

/// Wires a conversation session against in-memory audio and network doubles.
///
/// The fakes deliver their streams synchronously so a test can emit an event
/// and assert on the resulting snapshot without pumping the event loop for
/// state that does not cross an `await`.
final class ConversationTestDependencies {
  ConversationTestDependencies({
    AudioPreparationResult preparationResult = AudioPreparationResult.ready,
  }) : audioSession = FakeRealtimeAudioSession(preparationResult);

  final FakeRealtimeAudioSession audioSession;
  final FakeWiroApiClient apiClient = FakeWiroApiClient();
  final FakePcmAudioRecorder recorder = FakePcmAudioRecorder();
  final FakePcmAudioPlayer player = FakePcmAudioPlayer();
  final FakeRealtimeSession session = FakeRealtimeSession();
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  SpeechToSpeechSessionService createService() {
    return SpeechToSpeechSessionService(
      audioSession: audioSession,
      apiClient: apiClient,
      sessionFactory: ({
        required taskId,
        required taskToken,
      }) => session,
      recorder: recorder,
      player: player,
      sessionGuard: sessionGuard,
      terminalTimeout: Duration.zero,
    );
  }
}

final class FakeRealtimeAudioSession implements RealtimeAudioSession {
  FakeRealtimeAudioSession(this.result);

  final StreamController<RealtimeAudioInterruption> _interruptionController =
      StreamController<RealtimeAudioInterruption>.broadcast(sync: true);
  final StreamController<void> _becomingNoisyController =
      StreamController<void>.broadcast(sync: true);
  final StreamController<void> _routeController =
      StreamController<void>.broadcast(sync: true);
  final AudioPreparationResult result;
  final List<RealtimeAudioProfile> preparedProfiles = [];
  int deactivateCalls = 0;

  @override
  Stream<RealtimeAudioInterruption> get interruptions =>
      _interruptionController.stream;

  @override
  Stream<void> get becomingNoisy => _becomingNoisyController.stream;

  @override
  Stream<void> get routeChanges => _routeController.stream;

  @override
  Future<AudioPreparationResult> prepare(
    RealtimeAudioProfile profile,
  ) async {
    preparedProfiles.add(profile);
    return result;
  }

  @override
  Future<void> deactivate() async {
    deactivateCalls++;
  }

  @override
  Future<bool> setSpeakerEnabled({required bool enabled}) async => true;

  @override
  Future<void> dispose() async {
    await _interruptionController.close();
    await _becomingNoisyController.close();
    await _routeController.close();
  }

  void emitInterruption(RealtimeAudioInterruption interruption) {
    _interruptionController.add(interruption);
  }
}

final class FakeWiroApiClient implements WiroApiClient {
  int runCalls = 0;
  Map<String, Object?>? lastParameters;

  @override
  WiroRequestCancellation createCancellation() {
    return WiroRequestCancellation();
  }

  @override
  Future<WiroRunResult> runModel({
    required ModelDefinition model,
    required Map<String, Object?> parameters,
    WiroRequestCancellation? cancellation,
  }) async {
    runCalls++;
    lastParameters = parameters;
    return const WiroRunResult(
      taskId: 'task-id',
      taskToken: 'task-token',
    );
  }

  @override
  Future<void> terminateTaskBestEffort({
    required String taskId,
    required String taskToken,
  }) async {}
}

final class FakePcmAudioRecorder implements PcmAudioRecorder {
  StreamController<Uint8List>? _controller;
  bool _recording = false;
  bool _muted = false;

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  bool get isRecording => _recording;

  @override
  bool get isMuted => _muted;

  @override
  int get mutedSourceBuffers => 0;

  @override
  int get queueHighWaterMarkInChunks => 0;

  @override
  Future<Stream<Uint8List>> start(PcmCaptureProfile profile) async {
    startCalls++;
    _recording = true;
    _controller = StreamController<Uint8List>.broadcast(sync: true);
    return _controller!.stream;
  }

  @override
  void setMuted({required bool muted}) {
    _muted = muted;
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
    if (_recording && !_muted) {
      _controller?.add(bytes);
    }
  }
}

final class FakePcmAudioPlayer implements PcmAudioPlayer {
  final StreamController<AudioPlaybackFailure> _failureController =
      StreamController<AudioPlaybackFailure>.broadcast(sync: true);
  final List<List<int>> fedChunks = [];

  int startCalls = 0;
  int completeCalls = 0;
  int stopCalls = 0;
  int flushCalls = 0;
  int disposeCalls = 0;
  bool _playing = false;
  bool _enabled = true;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isEnabled => _enabled;

  @override
  Stream<AudioPlaybackFailure> get failures => _failureController.stream;

  @override
  int get droppedChunks => 0;

  @override
  int get maximumFeedLatencyMicros => 0;

  @override
  int get queueHighWaterMarkInChunks => 0;

  @override
  int get underrunCount => 0;

  @override
  Future<void> start() async {
    startCalls++;
    _playing = true;
  }

  @override
  Future<void> enqueue(Uint8List chunk) async {
    if (_playing && _enabled) {
      fedChunks.add(List<int>.from(chunk));
    }
  }

  @override
  bool tryEnqueue(Uint8List chunk) {
    if (_playing && _enabled) {
      fedChunks.add(List<int>.from(chunk));
      return true;
    }
    return false;
  }

  @override
  void flush() {
    flushCalls++;
    fedChunks.clear();
  }

  @override
  Future<void> complete() async {
    completeCalls++;
    _playing = false;
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {
    _enabled = enabled;
  }

  @override
  Future<void> stop() async {
    if (!_playing) {
      return;
    }
    stopCalls++;
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _playing = false;
  }
}

final class FakeRealtimeSession implements RealtimeSessionClient {
  final StreamController<RealtimeEvent> _eventsController =
      StreamController<RealtimeEvent>.broadcast(sync: true);
  final List<List<int>> sentAudio = [];

  int connectCalls = 0;
  int sessionEndCalls = 0;
  int closeCalls = 0;
  bool _ready = false;
  bool _closed = false;

  @override
  Stream<RealtimeEvent> get events => _eventsController.stream;

  @override
  bool get isReady => _ready && !_closed;

  @override
  bool get isClosed => _closed;

  @override
  RealtimeSessionMetrics get metrics => const RealtimeSessionMetrics.empty();

  @override
  Future<void> connect() async {
    connectCalls++;
    _ready = true;
  }

  @override
  bool sendAudio(Uint8List pcmBytes) {
    if (!isReady) {
      return false;
    }
    sentAudio.add(List<int>.from(pcmBytes));
    return true;
  }

  @override
  void sendSessionEnd() {
    if (_closed || sessionEndCalls > 0) {
      return;
    }
    sessionEndCalls++;
    emit(const RealtimeStatusEvent(RealtimeEventType.ended));
  }

  @override
  Future<void> stop() async {
    sendSessionEnd();
    await close();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    closeCalls++;
    _closed = true;
    _ready = false;
  }

  void emit(RealtimeEvent event) {
    _eventsController.add(event);
  }
}
