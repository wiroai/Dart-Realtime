import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_route_watcher.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/network/realtime_task_launcher.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/protocol_event_log.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_failure_mapper.dart';
import 'package:wiro_realtime/core/realtime/realtime_operation_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/core/realtime/session_elapsed_clock.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_playback_coordinator.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_transcript_parser.dart';

/// Runs a two-way speech conversation: microphone capture, the realtime socket,
/// assistant playback, and every way the session can end.
///
/// The service reports itself only through [snapshots] and never touches view
/// state, so the whole conversation lifecycle is testable without a widget
/// tree.
final class SpeechToSpeechSessionService
    implements ConversationSessionController {
  SpeechToSpeechSessionService({
    required this.audioSession,
    required this.apiClient,
    required this.sessionFactory,
    required this.recorder,
    required this.player,
    required this.sessionGuard,
    this.model = WiroModelCatalog.gptRealtimeMini,
    this.terminalTimeout = const Duration(seconds: 3),
  }) : parameters = ModelParameterValues(model.firstPassFields) {
    _routeWatcher = RealtimeAudioRouteWatcher(
      audioSession: audioSession,
      playbackFailures: player.failures,
      onShouldStop: _stopForAudioRouteSafety,
      onRouteChanged: _handleRouteChange,
      onPlaybackFailure: _handlePlayerFailure,
    );
  }

  final RealtimeAudioSession audioSession;
  final WiroApiClient apiClient;
  final RealtimeSessionFactory sessionFactory;
  final PcmAudioRecorder recorder;
  final PcmAudioPlayer player;
  final Duration terminalTimeout;

  @override
  final RealtimeSessionGuard sessionGuard;

  @override
  final ModelDefinition model;

  @override
  final ModelParameterValues parameters;

  static const ConversationTranscriptParser _transcriptParser =
      ConversationTranscriptParser();
  static const RealtimeFailureMapper _failureMapper = RealtimeFailureMapper(
    fallbackMessage: 'The conversation session could not be completed.',
  );

  /// Synchronous delivery keeps a snapshot observable the instant the session
  /// changes, the same way the view model's notifier behaved before the split.
  final StreamController<ConversationSessionSnapshot> _snapshots =
      StreamController<ConversationSessionSnapshot>.broadcast(sync: true);

  late final RealtimeAudioRouteWatcher _routeWatcher;
  late final RealtimeTaskLauncher _taskLauncher = RealtimeTaskLauncher(
    apiClient,
  );
  late final ConversationPlaybackCoordinator _playbackCoordinator =
      ConversationPlaybackCoordinator(player);
  final RealtimeOperationGuard _guard = RealtimeOperationGuard();
  final ProtocolEventLog _protocolLog = ProtocolEventLog();
  final SessionElapsedClock _elapsedClock = SessionElapsedClock();

  ConversationSessionSnapshot _snapshot = const ConversationSessionSnapshot();
  RealtimeSessionLease? _sessionLease;
  RealtimeSessionClient? _session;
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  StreamSubscription<Uint8List>? _pcmSubscription;
  Completer<void>? _terminalCompleter;
  Future<void>? _naturalCompletion;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  bool _naturalCompletionRunning = false;

  @override
  Stream<ConversationSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  ConversationSessionSnapshot get snapshot => _snapshot;

  @override
  Future<void> start() {
    if (_guard.isDisposed) {
      return Future<void>.value();
    }
    if (!_snapshot.sessionState.canStart) {
      return Future<void>.value();
    }
    final lease = sessionGuard.acquire(
      RealtimeSessionOwner.conversation,
    );
    if (lease == null) {
      _publish(
        _snapshot.copyWith(
          status: ViewStatus.error,
          sessionState: RealtimeSessionState.failure,
          errorMessage: const WiroSessionBusyFailure().message,
        ),
      );
      return Future<void>.value();
    }
    _sessionLease = lease;
    final operation = _start();
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
  }

  Future<void> _start() async {
    final operationId = _guard.begin();
    _protocolLog.clear();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.requestingPermission,
        elapsed: Duration.zero,
        userTranscript: '',
        aiTranscript: '',
        microphoneActive: false,
        errorMessage: null,
        protocolEvents: _protocolLog.events,
        revealProtocolPanel: false,
      ),
    );

    try {
      final preparation = await audioSession.prepare(
        RealtimeAudioProfile.conversation,
      );
      if (!_guard.isCurrent(operationId)) {
        await audioSession.deactivate();
        return;
      }
      if (preparation != AudioPreparationResult.ready) {
        await audioSession.deactivate();
        _releaseLease();
        _publish(
          _snapshot.copyWith(
            status: ViewStatus.error,
            sessionState: RealtimeSessionState.failure,
            errorMessage: preparation.errorMessage,
          ),
        );
        return;
      }

      _publish(
        _snapshot.copyWith(
          sessionState: RealtimeSessionState.preparingAudio,
        ),
      );
      _publish(
        _snapshot.copyWith(
          sessionState: RealtimeSessionState.creatingTask,
        ),
      );
      final runResult = await _taskLauncher.launch(
        model: model,
        parameters: parameters.requestSnapshot(),
        isStillWanted: () => _guard.isCurrent(operationId),
      );
      if (runResult == null) {
        return;
      }

      final session = sessionFactory(
        taskId: runResult.taskId,
        taskToken: runResult.taskToken,
      );
      _session = session;
      _terminalCompleter = Completer<void>();
      _naturalCompletion = null;
      _naturalCompletionRunning = false;
      _playbackCoordinator.reset();
      _eventSubscription = session.events.listen(
        (event) => _handleEvent(event, operationId),
        onError: (Object error) => _handleEventError(error, operationId),
        onDone: () => _handleEventStreamDone(operationId),
      );
      _publish(
        _snapshot.copyWith(
          sessionState: RealtimeSessionState.connectingSocket,
        ),
      );
      final connection = session.connect();
      await Future<void>.delayed(Duration.zero);
      if (_guard.isCurrent(operationId)) {
        _publish(
          _snapshot.copyWith(
            sessionState: RealtimeSessionState.waitingForStream,
          ),
        );
      }
      await connection;
      if (!_guard.isCurrent(operationId)) {
        await session.close();
        return;
      }

      final media = await (
        recorder.start(PcmCaptureProfile.conversation),
        player.start(),
      ).wait;
      final pcmStream = media.$1;
      if (!_guard.isCurrent(operationId)) {
        await recorder.stop();
        await player.stop();
        await session.close();
        return;
      }
      _pcmSubscription = pcmStream.listen(
        (chunk) => _sendPcm(chunk, operationId),
        onError: (Object error) => _handleAudioError(error, operationId),
      );
      _startElapsedTimer(operationId);
      _publish(
        _snapshot.copyWith(
          status: ViewStatus.success,
          sessionState: RealtimeSessionState.streaming,
          microphoneActive: !_snapshot.muted,
          protocolEvents: _protocolLog.add(
            'conversation_stream_started',
          ),
        ),
      );
    } on Object catch (error) {
      if (_guard.isCurrent(operationId)) {
        await _fail(operationId, error);
      }
    }
  }

  @override
  Future<void> stop() {
    if (_guard.isDisposed) {
      return Future<void>.value();
    }
    final pendingStop = _stopOperation;
    if (pendingStop != null) {
      return pendingStop;
    }
    if (!_snapshot.sessionState.canStop) {
      return Future<void>.value();
    }
    final operation = _stop();
    _stopOperation = operation;
    return operation.whenComplete(() {
      if (identical(_stopOperation, operation)) {
        _stopOperation = null;
      }
    });
  }

  Future<void> _stop() async {
    final operationId = _guard.begin();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.stopping,
        microphoneActive: false,
      ),
    );

    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    await _stopCapture();
    await player.stop();
    await _naturalCompletion;
    await audioSession.deactivate();

    var shutdownTimedOut = false;
    final session = _session;
    if (session != null && !session.isClosed) {
      final shouldWaitForTerminal = session.isReady;
      session.sendSessionEnd();
      final terminal = _terminalCompleter;
      if (shouldWaitForTerminal && terminal != null && !terminal.isCompleted) {
        try {
          await terminal.future.timeout(terminalTimeout);
        } on TimeoutException {
          shutdownTimedOut = true;
        }
      }
      await session.close();
    }
    await _startOperation;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _session = null;
    _terminalCompleter = null;
    _naturalCompletion = null;
    _taskLauncher.release();
    _releaseLease();

    if (!_guard.isCurrent(operationId)) {
      return;
    }
    _publish(
      _snapshot.copyWith(
        status: shutdownTimedOut ? ViewStatus.error : ViewStatus.success,
        sessionState: shutdownTimedOut
            ? RealtimeSessionState.failure
            : RealtimeSessionState.completed,
        microphoneActive: false,
        errorMessage: shutdownTimedOut
            ? const WiroShutdownTimeoutFailure().message
            : null,
        protocolEvents: _protocolLog.add(
          shutdownTimedOut ? 'shutdown_timeout' : 'session_stopped',
        ),
      ),
    );
  }

  @override
  void setMuted({required bool muted}) {
    if (_guard.isDisposed) {
      return;
    }
    recorder.setMuted(muted: muted);
    _publish(
      _snapshot.copyWith(
        muted: muted,
        microphoneActive:
            _snapshot.sessionState == RealtimeSessionState.streaming && !muted,
      ),
    );
  }

  @override
  void setSpeakerEnabled({required bool enabled}) {
    if (_guard.isDisposed) {
      return;
    }
    _publish(_snapshot.copyWith(speakerEnabled: enabled));
    unawaited(player.setEnabled(enabled: enabled));
  }

  @override
  Future<void> dispose() async {
    _guard.dispose();
    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    parameters.dispose();
    await _disposeResources();
    await _snapshots.close();
  }

  void _publish(ConversationSessionSnapshot next) {
    if (_guard.isDisposed || next == _snapshot) {
      return;
    }
    _snapshot = next;
    _snapshots.add(next);
  }

  void _sendPcm(Uint8List chunk, int operationId) {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    try {
      final sent = _session?.sendAudio(chunk) ?? false;
      if (!sent) {
        unawaited(_fail(operationId, const WiroSocketFailure()));
      }
    } on Object catch (error) {
      unawaited(_fail(operationId, error));
    }
  }

  void _handleEvent(RealtimeEvent event, int operationId) {
    if (event case RealtimeStatusEvent(
      type: RealtimeEventType.ended || RealtimeEventType.postprocessEnded,
    )) {
      _completeTerminalWait();
    }
    if (!_guard.isCurrent(operationId)) {
      return;
    }

    switch (event) {
      case RealtimeBinaryEvent():
        _queueAudio(event, operationId);
      case RealtimeOutputEvent():
        _handleOutput(event);
      case RealtimeStatusEvent(
        type: RealtimeEventType.streamEnded,
      ):
        _appendProtocolEvent(event.wireType);
        _finishAiTurn(operationId);
      case RealtimeStatusEvent(
        type: RealtimeEventType.ended,
      ):
        _appendProtocolEvent(event.wireType);
      case RealtimeStatusEvent(
        type: RealtimeEventType.postprocessEnded,
      ):
        _appendProtocolEvent(event.wireType);
        _naturalCompletion ??= _completeNaturally(operationId);
      case RealtimeErrorEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroSocketFailure()));
      case RealtimeCancelEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroCancellationFailure()));
      case RealtimeMalformedEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroProtocolFailure()));
      case RealtimeStatusEvent():
      case RealtimeUnknownEvent():
        _appendProtocolEvent(event.wireType);
    }
  }

  void _queueAudio(RealtimeBinaryEvent event, int operationId) {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    final outcome = _playbackCoordinator.enqueue(event.bytes);
    if (outcome.flushedPreviousTurn) {
      _appendProtocolEvent('previous_turn_dropped');
    }
    if (outcome.droppedChunk) {
      _appendProtocolEvent('audio_chunk_dropped');
    }
  }

  void _handleOutput(RealtimeOutputEvent event) {
    switch (_transcriptParser.parse(event.message)) {
      case UserTranscript(:final text):
        _publish(
          _snapshot.copyWith(
            userTranscript: text,
            protocolEvents: _protocolLog.add(event.wireType),
          ),
        );
      case AiTranscript(:final text):
        _publish(
          _snapshot.copyWith(
            aiTranscript: text,
            protocolEvents: _protocolLog.add(event.wireType),
          ),
        );
      case null:
        _appendProtocolEvent(event.wireType);
    }
  }

  /// Keeps playback running so the queued tail of this turn stays gapless.
  void _finishAiTurn(int operationId) {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    _playbackCoordinator.markTurnFinished();
    _publish(
      _snapshot.copyWith(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: !_snapshot.muted,
        protocolEvents: _protocolLog.add('listening_resumed'),
      ),
    );
  }

  Future<void> _completeNaturally(int operationId) async {
    if (!_guard.isCurrent(operationId) || _naturalCompletionRunning) {
      return;
    }
    _naturalCompletionRunning = true;
    await _stopCapture();
    await player.complete();
    await player.stop();
    await audioSession.deactivate();
    if (!_guard.isCurrent(operationId)) {
      _naturalCompletionRunning = false;
      return;
    }
    final completionId = _guard.begin();
    _elapsedClock.stop();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _naturalCompletion = null;
    _naturalCompletionRunning = false;
    _taskLauncher.release();
    _releaseLease();
    if (!_guard.isCurrent(completionId)) {
      return;
    }
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.success,
        sessionState: RealtimeSessionState.completed,
        microphoneActive: false,
      ),
    );
  }

  void _handleEventError(Object error, int operationId) {
    if (_guard.isCurrent(operationId)) {
      unawaited(_fail(operationId, error));
    }
  }

  void _handleEventStreamDone(int operationId) {
    final terminalReceived = _terminalCompleter?.isCompleted ?? false;
    if (_guard.isCurrent(operationId) && !terminalReceived) {
      unawaited(_fail(operationId, const WiroSocketFailure()));
    }
  }

  void _handleAudioError(Object error, int operationId) {
    if (_guard.isCurrent(operationId)) {
      unawaited(_fail(operationId, error));
    }
  }

  void _handlePlayerFailure(AudioPlaybackFailure failure) {
    if (_snapshot.sessionState.isActive) {
      unawaited(_fail(_guard.current, failure));
    }
  }

  Future<void> _fail(int operationId, Object error) async {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    final failureId = _guard.begin();
    _taskLauncher
      ..terminateBestEffort()
      ..cancelPendingRequest();
    _elapsedClock.stop();
    await _stopCapture();
    await player.stop();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _naturalCompletion = null;
    _naturalCompletionRunning = false;
    _releaseLease();
    if (!_guard.isCurrent(failureId)) {
      return;
    }
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        microphoneActive: false,
        errorMessage: _failureMapper.messageFor(error),
        revealProtocolPanel: true,
        protocolEvents: _protocolLog.add(
          'failure:${_failureMapper.codeFor(error)}',
        ),
      ),
    );
  }

  Future<void> _stopCapture() async {
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    await recorder.stop();
  }

  Future<void> _disposeResources() async {
    await _routeWatcher.dispose();
    await _stopCapture();
    await player.stop();
    await audioSession.deactivate();
    _session?.sendSessionEnd();
    _taskLauncher.terminateBestEffort();
    await _eventSubscription?.cancel();
    await _session?.close();
    await recorder.dispose();
    await player.dispose();
    _releaseLease();
  }

  void _stopForAudioRouteSafety() {
    if (_snapshot.sessionState.canStop) {
      unawaited(stop());
    }
  }

  void _handleRouteChange() {
    if (_snapshot.sessionState.isActive) {
      _appendProtocolEvent('audio_route_changed');
    }
  }

  void _releaseLease() {
    final lease = _sessionLease;
    _sessionLease = null;
    sessionGuard.release(lease);
  }

  void _startElapsedTimer(int operationId) {
    _elapsedClock.start((elapsed) {
      if (_guard.isCurrent(operationId)) {
        _publish(_snapshot.copyWith(elapsed: elapsed));
      }
    });
  }

  void _appendProtocolEvent(String event) {
    _publish(_snapshot.copyWith(protocolEvents: _protocolLog.add(event)));
  }

  void _completeTerminalWait() {
    final terminal = _terminalCompleter;
    if (terminal != null && !terminal.isCompleted) {
      terminal.complete();
    }
  }
}
