import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_metrics.dart';
import 'package:wiro_realtime/features/speech_to_text/service/speech_to_text_session_service.dart';

/// Wires a transcription session against in-memory audio and network doubles.
final class TranscriptionTestDependencies {
  TranscriptionTestDependencies({
    AudioPreparationResult preparationResult = AudioPreparationResult.ready,
    Completer<WiroRunResult>? runCompleter,
    bool ignoreRunCancellation = false,
    bool completeSessionEnd = true,
  }) : audioSession = FakeRealtimeAudioSession(preparationResult),
       apiClient = FakeWiroApiClient(
         runCompleter: runCompleter,
         ignoreRunCancellation: ignoreRunCancellation,
       ),
       session = FakeRealtimeSession(
         completeSessionEnd: completeSessionEnd,
       );

  final FakeRealtimeAudioSession audioSession;
  final FakeWiroApiClient apiClient;
  final FakePcmAudioRecorder recorder = FakePcmAudioRecorder();
  final FakeRealtimeSession session;
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  SpeechToTextSessionService createService() {
    return SpeechToTextSessionService(
      audioSession: audioSession,
      apiClient: apiClient,
      sessionFactory: ({
        required taskId,
        required taskToken,
      }) => session,
      recorder: recorder,
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
  Future<bool> openSystemSettings() async => true;

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
  FakeWiroApiClient({
    this.runCompleter,
    this.ignoreRunCancellation = false,
  });

  final Completer<WiroRunResult>? runCompleter;
  final bool ignoreRunCancellation;
  final List<String> terminatedTaskIds = [];
  int runCalls = 0;
  Map<String, Object?>? lastParameters;
  WiroRequestCancellation? lastCancellation;

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
    lastCancellation = cancellation;
    final pendingRun = runCompleter;
    if (pendingRun == null) {
      return const WiroRunResult(
        taskId: 'task-id',
        taskToken: 'task-token',
      );
    }
    if (ignoreRunCancellation) {
      return pendingRun.future;
    }
    return Future.any<WiroRunResult>([
      pendingRun.future,
      cancellation!.whenCancelled.then<WiroRunResult>((_) {
        throw const WiroCancellationFailure();
      }),
    ]);
  }

  @override
  Future<void> terminateTaskBestEffort({
    required String taskId,
    required String taskToken,
  }) async {
    terminatedTaskIds.add(taskId);
  }
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
    _controller?.add(bytes);
  }
}

final class FakeRealtimeSession implements RealtimeSessionClient {
  FakeRealtimeSession({required this.completeSessionEnd});

  final bool completeSessionEnd;
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
    if (completeSessionEnd) {
      emit(
        const RealtimeStatusEvent(
          RealtimeEventType.postprocessEnded,
        ),
      );
    }
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
