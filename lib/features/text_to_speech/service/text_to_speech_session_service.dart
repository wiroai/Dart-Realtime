import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
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
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_controller.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_snapshot.dart';

/// Owns task creation, realtime audio playback, and session termination.
final class TextToSpeechSessionService implements SpeechSessionController {
  TextToSpeechSessionService({
    required this.audioSession,
    required this.apiClient,
    required this.sessionFactory,
    required this.player,
    required this.sessionGuard,
    ModelDefinition model = WiroModelCatalog.mossTtsRealtime,
    this.terminalTimeout = const Duration(seconds: 3),
  }) : _selectedModel = model,
       _parameters = ModelParameterValues(model.firstPassFields),
       _snapshot = SpeechSessionSnapshot(selectedModel: model) {
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
  final PcmAudioPlayer player;
  final Duration terminalTimeout;

  @override
  final RealtimeSessionGuard sessionGuard;

  static const RealtimeFailureMapper _failureMapper = RealtimeFailureMapper(
    fallbackMessage: 'The speech session could not be completed.',
  );

  final StreamController<SpeechSessionSnapshot> _snapshots =
      StreamController<SpeechSessionSnapshot>.broadcast(sync: true);
  final RealtimeOperationGuard _guard = RealtimeOperationGuard();
  final ProtocolEventLog _protocolLog = ProtocolEventLog();
  final SessionElapsedClock _elapsedClock = SessionElapsedClock();

  late final RealtimeAudioRouteWatcher _routeWatcher;
  late final RealtimeTaskLauncher _taskLauncher = RealtimeTaskLauncher(
    apiClient,
  );

  ModelDefinition _selectedModel;
  ModelParameterValues _parameters;
  SpeechSessionSnapshot _snapshot;
  RealtimeSessionLease? _sessionLease;
  RealtimeSessionClient? _session;
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  Completer<void>? _terminalCompleter;
  Future<void>? _playbackCompletion;
  Future<void>? _naturalCompletion;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  bool _naturalCompletionRunning = false;

  @override
  Stream<SpeechSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  SpeechSessionSnapshot get snapshot => _snapshot;

  @override
  ModelParameterValues get parameters => _parameters;

  @override
  ValueNotifier<String> get promptNotifier {
    return _parameters.require(_promptFieldId);
  }

  @override
  void selectModel(ModelDefinition model) {
    if (_guard.isDisposed ||
        _snapshot.sessionState.isActive ||
        model.direction != RealtimeDirection.textToSpeech) {
      return;
    }
    final previous = _parameters;
    _selectedModel = model;
    _parameters = ModelParameterValues(model.firstPassFields);
    previous.dispose();
    _publish(
      _snapshot.copyWith(
        selectedModel: model,
        errorMessage: null,
      ),
    );
  }

  @override
  Future<void> start() {
    if (_guard.isDisposed || !_snapshot.sessionState.canStart) {
      return Future<void>.value();
    }
    final prompt = promptNotifier.value.trim();
    if (prompt.isEmpty) {
      _publish(
        _snapshot.copyWith(
          status: ViewStatus.error,
          sessionState: RealtimeSessionState.failure,
          errorMessage: 'Enter text to synthesize.',
        ),
      );
      return Future<void>.value();
    }
    final lease = sessionGuard.acquire(RealtimeSessionOwner.speech);
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
    final operation = _start(prompt);
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
  }

  Future<void> _start(String prompt) async {
    final operationId = _guard.begin();
    _protocolLog.clear();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.preparingAudio,
        elapsed: Duration.zero,
        isPlaying: false,
        errorMessage: null,
        protocolEvents: _protocolLog.events,
        revealProtocolPanel: false,
      ),
    );

    try {
      final preparation = await audioSession.prepare(
        RealtimeAudioProfile.speech,
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
          sessionState: RealtimeSessionState.creatingTask,
        ),
      );
      final request = _parameters.requestSnapshot();
      request[_promptFieldId] = prompt;
      final runResult = await _taskLauncher.launch(
        model: _selectedModel,
        parameters: request,
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
      _playbackCompletion = null;
      _naturalCompletion = null;
      _naturalCompletionRunning = false;
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

      await player.start();
      if (!_guard.isCurrent(operationId)) {
        await player.stop();
        await session.close();
        return;
      }
      _startElapsedTimer(operationId);
      _publish(
        _snapshot.copyWith(
          status: ViewStatus.success,
          sessionState: RealtimeSessionState.streaming,
          protocolEvents: _protocolLog.add(
            'playback_stream_started',
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
        isPlaying: false,
      ),
    );

    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
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
    _clearSessionReferences();
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
        isPlaying: false,
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
  Future<void> dispose() async {
    if (_guard.isDisposed) {
      return;
    }
    _guard.dispose();
    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    _parameters.dispose();
    await _routeWatcher.dispose();
    await player.stop();
    await audioSession.deactivate();
    _session?.sendSessionEnd();
    _taskLauncher.terminateBestEffort();
    await _eventSubscription?.cancel();
    await _session?.close();
    await player.dispose();
    _clearSessionReferences();
    _releaseLease();
    await _snapshots.close();
  }

  void _handleEvent(RealtimeEvent event, int operationId) {
    if (event case RealtimeStatusEvent(
      type: RealtimeEventType.postprocessEnded,
    )) {
      _completeTerminalWait();
    }
    if (!_guard.isCurrent(operationId)) {
      return;
    }

    switch (event) {
      case RealtimeBinaryEvent():
        _queueAudio(event, operationId);
      case RealtimeStatusEvent(
        type: RealtimeEventType.streamEnded,
      ):
        _appendProtocolEvent(event.wireType);
        _publish(
          _snapshot.copyWith(
            sessionState: RealtimeSessionState.stopping,
          ),
        );
        _playbackCompletion ??= _finishPlayback(operationId);
      case RealtimeStatusEvent(
        type: RealtimeEventType.postprocessEnded,
      ):
        _appendProtocolEvent(event.wireType);
        _naturalCompletion ??= _completeNaturally(operationId);
      // Interim stderr from the model; the session is still alive.
      case RealtimeErrorEvent():
        _appendProtocolEvent(event.wireType);
      case RealtimeCancelEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroCancellationFailure()));
      case RealtimeMalformedEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroProtocolFailure()));
      case RealtimeOutputEvent():
      case RealtimeStatusEvent():
      case RealtimeUnknownEvent():
        _appendProtocolEvent(event.wireType);
    }
  }

  void _queueAudio(RealtimeBinaryEvent event, int operationId) {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    if (!_snapshot.isPlaying) {
      _publish(_snapshot.copyWith(isPlaying: true));
    }
    if (!player.tryEnqueue(event.bytes)) {
      _appendProtocolEvent('audio_chunk_dropped');
    }
  }

  Future<void> _finishPlayback(int operationId) async {
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    await player.complete();
    if (_guard.isCurrent(operationId)) {
      _publish(_snapshot.copyWith(isPlaying: false));
    }
  }

  Future<void> _completeNaturally(int operationId) async {
    if (!_guard.isCurrent(operationId) || _naturalCompletionRunning) {
      return;
    }
    _naturalCompletionRunning = true;
    _playbackCompletion ??= _finishPlayback(operationId);
    await _playbackCompletion;
    if (!_guard.isCurrent(operationId)) {
      _naturalCompletionRunning = false;
      return;
    }
    final completionId = _guard.begin();
    _elapsedClock.stop();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    await _session?.close();
    _clearSessionReferences();
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
        isPlaying: false,
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
    await player.stop();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    await _session?.close();
    _clearSessionReferences();
    _naturalCompletionRunning = false;
    _releaseLease();
    if (!_guard.isCurrent(failureId)) {
      return;
    }
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        isPlaying: false,
        errorMessage: _failureMapper.messageFor(error),
        revealProtocolPanel: true,
        protocolEvents: _protocolLog.add(
          'failure:${_failureMapper.codeFor(error)}',
        ),
      ),
    );
  }

  void _clearSessionReferences() {
    _eventSubscription = null;
    _session = null;
    _terminalCompleter = null;
    _playbackCompletion = null;
    _naturalCompletion = null;
  }

  void _publish(SpeechSessionSnapshot next) {
    if (_guard.isDisposed || next == _snapshot) {
      return;
    }
    _snapshot = next;
    _snapshots.add(next);
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
    _publish(
      _snapshot.copyWith(
        protocolEvents: _protocolLog.add(event),
      ),
    );
  }

  void _completeTerminalWait() {
    final terminal = _terminalCompleter;
    if (terminal != null && !terminal.isCompleted) {
      terminal.complete();
    }
  }

  String get _promptFieldId {
    return _selectedModel.modelSlug ==
            WiroModelCatalog.mossTtsRealtime.modelSlug
        ? 'text'
        : 'prompt';
  }
}
