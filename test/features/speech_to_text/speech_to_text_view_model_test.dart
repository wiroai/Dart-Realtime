import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
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
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';

void main() {
  test('runs Voxtral and streams prefixed PCM after readiness', () async {
    final dependencies = SttTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.start();
    dependencies.recorder.emit(Uint8List.fromList([1, 2, 3]));
    await pumpEventQueue();

    expect(
      dependencies.audioSession.preparedProfiles,
      [RealtimeAudioProfile.transcription],
    );
    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.apiClient.lastParameters, {
      'transcriptionDelay': 'balanced',
    });
    expect(dependencies.session.sentAudio, [
      [1, 2, 3],
    ]);
    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.microphoneActive, isTrue);
  });

  test('replaces transcript with each authoritative output', () async {
    final dependencies = SttTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello world'));

    expect(viewModel.state.transcript, 'Hello world');
    expect(
      viewModel.state.protocolEvents.where(
        (event) => event == 'task_output',
      ),
      hasLength(2),
    );
  });

  test('stop releases microphone and sends one session end', () async {
    final dependencies = SttTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    final firstStop = viewModel.stop();
    final secondStop = viewModel.stop();
    await Future.wait([firstStop, secondStop]);

    expect(dependencies.recorder.stopCalls, 1);
    expect(dependencies.audioSession.deactivateCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
    expect(viewModel.state.microphoneActive, isFalse);
  });

  test('maps denied microphone permission without running a task', () async {
    final dependencies = SttTestDependencies(
      preparationResult: AudioPreparationResult.permissionDenied,
    );
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
    expect(viewModel.state.errorMessage, isNotEmpty);
  });

  test('cancels a pending Run request during stop', () async {
    final runCompleter = Completer<WiroRunResult>();
    final dependencies = SttTestDependencies(
      runCompleter: runCompleter,
    );
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    final starting = viewModel.start();
    await pumpEventQueue();

    await viewModel.stop();
    await starting;

    expect(dependencies.apiClient.lastCancellation?.isCancelled, isTrue);
    expect(dependencies.session.connectCalls, 0);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
  });

  test('terminates a Run result that arrives after stop', () async {
    final runCompleter = Completer<WiroRunResult>();
    final dependencies = SttTestDependencies(
      runCompleter: runCompleter,
      ignoreRunCancellation: true,
    );
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    final starting = viewModel.start();
    await pumpEventQueue();

    final stopping = viewModel.stop();
    runCompleter.complete(
      const WiroRunResult(
        taskId: 'orphan-task',
        taskToken: 'orphan-token',
      ),
    );
    await Future.wait([starting, stopping]);
    await pumpEventQueue();

    expect(dependencies.apiClient.terminatedTaskIds, ['orphan-task']);
    expect(dependencies.session.connectCalls, 0);
  });

  test('completes naturally after postprocess end', () async {
    final dependencies = SttTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.streamEnded),
      )
      ..emit(
        const RealtimeStatusEvent(
          RealtimeEventType.postprocessEnded,
        ),
      );
    await pumpEventQueue();

    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
    expect(viewModel.state.microphoneActive, isFalse);
    expect(dependencies.recorder.stopCalls, 1);
  });

  test('rejects unexpected server audio for STT', () async {
    final dependencies = SttTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([1, 2])),
    );
    await pumpEventQueue();

    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
    expect(viewModel.state.errorMessage, isNot(contains('1, 2')));
  });
}

final class SttTestDependencies {
  SttTestDependencies({
    AudioPreparationResult preparationResult = AudioPreparationResult.ready,
    Completer<WiroRunResult>? runCompleter,
    bool ignoreRunCancellation = false,
  }) : audioSession = FakeRealtimeAudioSession(preparationResult),
       apiClient = FakeWiroApiClient(
         runCompleter: runCompleter,
         ignoreRunCancellation: ignoreRunCancellation,
       );

  final FakeRealtimeAudioSession audioSession;
  final FakeWiroApiClient apiClient;
  final FakePcmAudioRecorder recorder = FakePcmAudioRecorder();
  final FakeRealtimeSession session = FakeRealtimeSession();
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  SpeechToTextViewModel createViewModel() {
    return SpeechToTextViewModel(
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

  final AudioPreparationResult result;
  final List<RealtimeAudioProfile> preparedProfiles = [];
  int deactivateCalls = 0;

  @override
  Stream<RealtimeAudioInterruption> get interruptions => const Stream.empty();

  @override
  Stream<void> get becomingNoisy => const Stream.empty();

  @override
  Stream<void> get routeChanges => const Stream.empty();

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
  Future<void> dispose() async {}
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
    emit(
      const RealtimeStatusEvent(
        RealtimeEventType.postprocessEnded,
      ),
    );
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
