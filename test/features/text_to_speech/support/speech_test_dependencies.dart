import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_metrics.dart';
import 'package:wiro_realtime/features/text_to_speech/service/text_to_speech_session_service.dart';

final class SpeechTestDependencies {
  SpeechTestDependencies({
    AudioPreparationResult preparationResult = AudioPreparationResult.ready,
    Completer<WiroRunResult>? runCompleter,
    bool ignoreRunCancellation = false,
    bool completeSessionEnd = true,
    Completer<void>? playbackCompleter,
  }) : audioSession = FakeRealtimeAudioSession(preparationResult),
       apiClient = FakeWiroApiClient(
         runCompleter: runCompleter,
         ignoreRunCancellation: ignoreRunCancellation,
       ),
       player = FakePcmAudioPlayer(playbackCompleter),
       session = FakeRealtimeSession(
         completeSessionEnd: completeSessionEnd,
       );

  final FakeRealtimeAudioSession audioSession;
  final FakeWiroApiClient apiClient;
  final FakePcmAudioPlayer player;
  final FakeRealtimeSession session;
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  TextToSpeechSessionService createService({
    ModelDefinition? model,
  }) {
    return TextToSpeechSessionService(
      audioSession: audioSession,
      apiClient: apiClient,
      sessionFactory: ({
        required taskId,
        required taskToken,
      }) => session,
      player: player,
      sessionGuard: sessionGuard,
      model: model ?? WiroModelCatalog.mossTtsRealtime,
      terminalTimeout: Duration.zero,
    );
  }
}

final class FakeRealtimeAudioSession implements RealtimeAudioSession {
  FakeRealtimeAudioSession(this.result);

  final StreamController<RealtimeAudioInterruption> _interruptions =
      StreamController<RealtimeAudioInterruption>.broadcast(sync: true);
  final StreamController<void> _noisy = StreamController<void>.broadcast(
    sync: true,
  );
  final StreamController<void> _routes = StreamController<void>.broadcast(
    sync: true,
  );
  final AudioPreparationResult result;
  final List<RealtimeAudioProfile> preparedProfiles = [];
  int deactivateCalls = 0;

  @override
  Stream<RealtimeAudioInterruption> get interruptions => _interruptions.stream;

  @override
  Stream<void> get becomingNoisy => _noisy.stream;

  @override
  Stream<void> get routeChanges => _routes.stream;

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
    await _interruptions.close();
    await _noisy.close();
    await _routes.close();
  }

  void emitInterruption(RealtimeAudioInterruption interruption) {
    _interruptions.add(interruption);
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
    final pending = runCompleter;
    if (pending == null) {
      return const WiroRunResult(
        taskId: 'task-id',
        taskToken: 'task-token',
      );
    }
    if (ignoreRunCancellation) {
      return pending.future;
    }
    return Future.any<WiroRunResult>([
      pending.future,
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

final class FakePcmAudioPlayer implements PcmAudioPlayer {
  FakePcmAudioPlayer(this.playbackCompleter);

  final Completer<void>? playbackCompleter;
  final StreamController<AudioPlaybackFailure> _failures =
      StreamController<AudioPlaybackFailure>.broadcast(sync: true);
  final List<List<int>> fedChunks = [];
  int startCalls = 0;
  int completeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isEnabled => true;

  @override
  Stream<AudioPlaybackFailure> get failures => _failures.stream;

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
    tryEnqueue(chunk);
  }

  @override
  bool tryEnqueue(Uint8List chunk) {
    if (!_playing) {
      return false;
    }
    fedChunks.add(List<int>.from(chunk));
    return true;
  }

  @override
  void flush() {
    fedChunks.clear();
  }

  @override
  Future<void> complete() async {
    completeCalls++;
    await playbackCompleter?.future;
    _playing = false;
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {}

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
    await _failures.close();
  }

  void emitFailure() {
    _failures.add(const AudioPlaybackFailure());
  }
}

final class FakeRealtimeSession implements RealtimeSessionClient {
  FakeRealtimeSession({required this.completeSessionEnd});

  final bool completeSessionEnd;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast(sync: true);
  int connectCalls = 0;
  int sessionEndCalls = 0;
  int closeCalls = 0;
  bool _ready = false;
  bool _closed = false;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

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
    _events.add(event);
  }
}
