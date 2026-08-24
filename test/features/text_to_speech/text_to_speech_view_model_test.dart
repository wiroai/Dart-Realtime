import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
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
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

void main() {
  test('requires non-empty text before starting a task', () async {
    final dependencies = TtsTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(dependencies.audioSession.preparedProfiles, isEmpty);
    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
  });

  test('runs MOSS and prepares playback without microphone access', () async {
    final dependencies = TtsTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    viewModel.promptNotifier.value = '  Hello realtime speech.  ';

    await viewModel.start();

    expect(
      dependencies.audioSession.preparedProfiles,
      [RealtimeAudioProfile.speech],
    );
    expect(dependencies.apiClient.lastParameters, {
      'text': 'Hello realtime speech.',
    });
    expect(dependencies.session.connectCalls, 1);
    expect(dependencies.player.startCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.isPlaying, isFalse);
  });

  test(
    'queues server PCM in FIFO order and drains before completion',
    () async {
      final dependencies = TtsTestDependencies();
      final viewModel = dependencies.createViewModel();
      addTearDown(viewModel.dispose);
      viewModel.promptNotifier.value = 'Hello';
      await viewModel.start();

      dependencies.session
        ..emit(RealtimeBinaryEvent(Uint8List.fromList([1, 2])))
        ..emit(RealtimeBinaryEvent(Uint8List.fromList([3, 4])))
        ..emit(
          const RealtimeStatusEvent(RealtimeEventType.streamEnded),
        )
        ..emit(
          const RealtimeStatusEvent(
            RealtimeEventType.postprocessEnded,
          ),
        );
      await pumpEventQueue();

      expect(dependencies.player.fedChunks, [
        [1, 2],
        [3, 4],
      ]);
      expect(dependencies.player.completeCalls, 1);
      expect(viewModel.state.sessionState, RealtimeSessionState.completed);
      expect(viewModel.state.isPlaying, isFalse);
    },
  );

  test('early stop flushes playback and ends the session once', () async {
    final dependencies = TtsTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    viewModel.promptNotifier.value = 'Hello';
    await viewModel.start();
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([1, 2])),
    );

    final firstStop = viewModel.stop();
    final secondStop = viewModel.stop();
    await Future.wait([firstStop, secondStop]);

    expect(dependencies.player.stopCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(dependencies.audioSession.deactivateCalls, 1);
    expect(viewModel.state.sessionState, RealtimeSessionState.completed);
  });

  test('maps playback failures to a sanitized recoverable state', () async {
    final dependencies = TtsTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    viewModel.promptNotifier.value = 'Hello';
    await viewModel.start();

    dependencies.player.emitFailure();
    await pumpEventQueue();

    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
    expect(viewModel.state.errorMessage, isNot(contains('platform')));
  });

  test('rejects malformed realtime audio frames', () async {
    final dependencies = TtsTestDependencies();
    final viewModel = dependencies.createViewModel();
    addTearDown(viewModel.dispose);
    viewModel.promptNotifier.value = 'Hello';
    await viewModel.start();

    dependencies.session.emit(const RealtimeMalformedEvent());
    await pumpEventQueue();

    expect(viewModel.state.status, ViewStatus.error);
    expect(viewModel.state.sessionState, RealtimeSessionState.failure);
  });
}

final class TtsTestDependencies {
  final FakeRealtimeAudioSession audioSession = FakeRealtimeAudioSession();
  final FakeWiroApiClient apiClient = FakeWiroApiClient();
  final FakePcmAudioPlayer player = FakePcmAudioPlayer();
  final FakeRealtimeSession session = FakeRealtimeSession();
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  TextToSpeechViewModel createViewModel() {
    return TextToSpeechViewModel(
      audioSession: audioSession,
      apiClient: apiClient,
      sessionFactory: ({
        required taskId,
        required taskToken,
      }) => session,
      player: player,
      sessionGuard: sessionGuard,
      terminalTimeout: Duration.zero,
    );
  }
}

final class FakeRealtimeAudioSession implements RealtimeAudioSession {
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
    return AudioPreparationResult.ready;
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

  void emitFailure() {
    _failureController.add(const AudioPlaybackFailure());
  }
}

final class FakeRealtimeSession implements RealtimeSessionClient {
  final StreamController<RealtimeEvent> _eventsController =
      StreamController<RealtimeEvent>.broadcast(sync: true);

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
  bool sendAudio(Uint8List pcmBytes) => false;

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
