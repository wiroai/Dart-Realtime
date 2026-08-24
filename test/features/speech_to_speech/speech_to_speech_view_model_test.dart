import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
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
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

void main() {
  test('starts GPT Realtime with verified PCM parameters', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.start();

    expect(
      dependencies.audioSession.preparedProfiles,
      [RealtimeAudioProfile.conversation],
    );
    expect(
      dependencies.apiClient.lastParameters,
      containsPair(
        'input_audio_format',
        'audio/pcm',
      ),
    );
    expect(
      dependencies.apiClient.lastParameters,
      containsPair(
        'output_audio_format',
        'audio/pcm',
      ),
    );
    expect(
      dependencies.apiClient.lastParameters,
      containsPair(
        'input_audio_rate',
        '24000',
      ),
    );
    expect(
      dependencies.apiClient.lastParameters,
      containsPair(
        'output_audio_rate',
        '24000',
      ),
    );
    expect(dependencies.recorder.startCalls, 1);
    expect(dependencies.player.startCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.microphoneActive, isTrue);
  });

  test('streams microphone and assistant PCM concurrently', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.recorder.emit(Uint8List.fromList([1, 2]));
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([3, 4])),
    );
    await pumpEventQueue();

    expect(dependencies.session.sentAudio, [
      [1, 2],
    ]);
    expect(dependencies.player.fedChunks, [
      [3, 4],
    ]);
  });

  test('keeps microphone streaming while the AI is speaking', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([3, 4])),
    );
    dependencies.recorder.emit(Uint8List.fromList([5]));

    expect(dependencies.session.sentAudio, [
      [5],
    ]);
    expect(viewModel.state.microphoneActive, isTrue);
  });

  test('a user transcript alone never cuts assistant audio', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session
      ..emit(
        RealtimeBinaryEvent(Uint8List.fromList([1])),
      )
      ..emit(
        const RealtimeOutputEvent('TRANSCRIPT_USER:Stop'),
      );
    await pumpEventQueue();
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([2])),
    );

    expect(dependencies.player.flushCalls, 0);
    expect(dependencies.player.stopCalls, 0);
    expect(dependencies.player.fedChunks, [
      [1],
      [2],
    ]);
    expect(viewModel.state.userTranscript, 'Stop');
  });

  test('a new assistant turn drops the interrupted turn tail', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session
      ..emit(
        RealtimeBinaryEvent(Uint8List.fromList([1])),
      )
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.streamEnded),
      )
      ..emit(
        RealtimeBinaryEvent(Uint8List.fromList([2])),
      )
      ..emit(
        RealtimeBinaryEvent(Uint8List.fromList([3])),
      );
    await pumpEventQueue();

    expect(dependencies.player.flushCalls, 1);
    expect(dependencies.player.fedChunks, [
      [2],
      [3],
    ]);
    expect(
      viewModel.state.protocolEvents,
      contains('previous_turn_dropped'),
    );
  });

  test('assigns progressive transcripts to the correct role', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session
      ..emit(
        const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'),
      )
      ..emit(
        const RealtimeOutputEvent('TRANSCRIPT_AI:Hi there'),
      )
      ..emit(
        const RealtimeOutputEvent('TRANSCRIPT_USER:Hello world'),
      );

    expect(viewModel.state.userTranscript, 'Hello world');
    expect(viewModel.state.aiTranscript, 'Hi there');
  });

  test('mute drops microphone audio without closing the session', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    viewModel.muteChanged(muted: true);
    dependencies.recorder.emit(Uint8List.fromList([1]));
    viewModel.muteChanged(muted: false);
    dependencies.recorder.emit(Uint8List.fromList([2]));
    await pumpEventQueue();

    expect(dependencies.session.sentAudio, [
      [2],
    ]);
    expect(dependencies.session.closeCalls, 0);
    expect(viewModel.state.microphoneActive, isTrue);
  });

  test('speaker disable preserves microphone streaming', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    viewModel.speakerChanged(enabled: false);
    dependencies.recorder.emit(Uint8List.fromList([7]));
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([8])),
    );
    await pumpEventQueue();

    expect(dependencies.player.isEnabled, isFalse);
    expect(dependencies.session.sentAudio, [
      [7],
    ]);
    expect(dependencies.player.fedChunks, isEmpty);
    expect(dependencies.session.closeCalls, 0);
  });

  test('stop releases all media and sends one session end', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    final firstStop = viewModel.stop();
    final secondStop = viewModel.stop();
    await Future.wait([firstStop, secondStop]);

    expect(dependencies.recorder.stopCalls, 1);
    expect(dependencies.player.stopCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
    expect(viewModel.state.microphoneActive, isFalse);
  });

  test('AI turn end resumes listening without closing the session', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([1, 2])),
    );

    dependencies.session
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.streamEnded),
      )
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.ended),
      );
    await pumpEventQueue();

    expect(dependencies.player.completeCalls, 0);
    expect(dependencies.player.startCalls, 1);
    expect(dependencies.player.fedChunks, [
      [1, 2],
    ]);
    expect(dependencies.recorder.stopCalls, 0);
    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.microphoneActive, isTrue);
  });

  test('postprocess end drains media and completes the session', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.session.emit(
      const RealtimeStatusEvent(
        RealtimeEventType.postprocessEnded,
      ),
    );
    await pumpEventQueue();

    expect(dependencies.player.completeCalls, 1);
    expect(dependencies.recorder.stopCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
  });

  test('permission denial does not create a task', () async {
    final dependencies = ConversationTestDependencies(
      preparationResult: AudioPreparationResult.permissionDenied,
    );
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
  });

  test('stops an active session when audio is interrupted', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    dependencies.audioSession.emitInterruption(
      RealtimeAudioInterruption.began,
    );
    await pumpEventQueue();

    expect(dependencies.session.sessionEndCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
  });

  test('keeps the local protocol history bounded', () async {
    final dependencies = ConversationTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    await viewModel.start();

    for (var index = 0; index < 50; index++) {
      dependencies.session.emit(
        RealtimeUnknownEvent('future_event_$index'),
      );
    }

    expect(viewModel.state.protocolEvents, hasLength(40));
  });
}

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

  SpeechToSpeechViewModel createViewModel() {
    return SpeechToSpeechViewModel(
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
