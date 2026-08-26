import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
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
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_snapshot.dart';

/// Runs microphone capture and the realtime transcription session.
final class SpeechToTextSessionService
    implements TranscriptionSessionController {
  SpeechToTextSessionService({
    required this.audioSession,
    required this.apiClient,
    required this.sessionFactory,
    required this.recorder,
    required this.sessionGuard,
    this.model = WiroModelCatalog.voxtralMiniRealtime,
    this.terminalTimeout = const Duration(seconds: 3),
  }) : parameters = ModelParameterValues(model.firstPassFields) {
    _routeWatcher = RealtimeAudioRouteWatcher(
      audioSession: audioSession,
      playbackFailures: const Stream<AudioPlaybackFailure>.empty(),
      onShouldStop: _stopForAudioRouteSafety,
      onRouteChanged: _handleRouteChange,
      onPlaybackFailure: (_) {},
    );
  }

  final RealtimeAudioSession audioSession;
  final WiroApiClient apiClient;
  final RealtimeSessionFactory sessionFactory;
  final PcmAudioRecorder recorder;
  final Duration terminalTimeout;

  @override
  final RealtimeSessionGuard sessionGuard;

  @override
  final ModelDefinition model;

  @override
  final ModelParameterValues parameters;

  static const String _transcriptPrefix = 'TRANSCRIPT_USER:';
  static const RealtimeFailureMapper _failureMapper = RealtimeFailureMapper(
    fallbackMessage: 'The transcription session could not be completed.',
  );

  final StreamController<TranscriptionSessionSnapshot> _snapshots =
      StreamController<TranscriptionSessionSnapshot>.broadcast(sync: true);
  final RealtimeOperationGuard _guard = RealtimeOperationGuard();
  final ProtocolEventLog _protocolLog = ProtocolEventLog();
  final SessionElapsedClock _elapsedClock = SessionElapsedClock();

  late final RealtimeAudioRouteWatcher _routeWatcher;
  late final RealtimeTaskLauncher _taskLauncher = RealtimeTaskLauncher(
    apiClient,
  );

  TranscriptionSessionSnapshot _snapshot = const TranscriptionSessionSnapshot();
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
  Stream<TranscriptionSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  TranscriptionSessionSnapshot get snapshot => _snapshot;

  @override
  Future<void> start() {
    if (_guard.isDisposed || !_snapshot.sessionState.canStart) {
      return Future<void>.value();
    }
    final lease = sessionGuard.acquire(
      RealtimeSessionOwner.transcription,
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
        transcript: '',
        microphoneActive: false,
        errorMessage: null,
        protocolEvents: _protocolLog.events,
        revealProtocolPanel: false,
      ),
    );

    try {
      final preparation = await audioSession.prepare(
        RealtimeAudioProfile.transcription,
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

      final pcmStream = await recorder.start(
        PcmCaptureProfile.transcription,
      );
      if (!_guard.isCurrent(operationId)) {
        await recorder.stop();
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
          microphoneActive: true,
          protocolEvents: _protocolLog.add(
            'microphone_stream_started',
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
  void clearTranscript() {
    if (_guard.isDisposed || _snapshot.sessionState.isActive) {
      return;
    }
    _publish(_snapshot.copyWith(transcript: ''));
  }

  @override
  Future<void> dispose() async {
    if (_guard.isDisposed) {
      return;
    }
    _guard.dispose();
    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    parameters.dispose();
    await _disposeResources();
    await _snapshots.close();
  }

  void _publish(TranscriptionSessionSnapshot next) {
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
      type: RealtimeEventType.postprocessEnded,
    )) {
      _completeTerminalWait();
    }
    if (!_guard.isCurrent(operationId)) {
      return;
    }

    switch (event) {
      case RealtimeOutputEvent():
        _handleOutput(event);
      case RealtimeStatusEvent(
        type: RealtimeEventType.streamEnded,
      ):
        _appendProtocolEvent(event.wireType);
        unawaited(_handleStreamEnded(operationId));
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
      case RealtimeBinaryEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroProtocolFailure()));
      case RealtimeStatusEvent():
      case RealtimeUnknownEvent():
        _appendProtocolEvent(event.wireType);
    }
  }

  void _handleOutput(RealtimeOutputEvent event) {
    final message = event.message;
    if (!message.startsWith(_transcriptPrefix)) {
      _appendProtocolEvent(event.wireType);
      return;
    }
    _publish(
      _snapshot.copyWith(
        transcript: message.substring(_transcriptPrefix.length),
        protocolEvents: _protocolLog.add(event.wireType),
      ),
    );
  }

  Future<void> _handleStreamEnded(int operationId) async {
    await _stopCapture();
    await audioSession.deactivate();
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    _publish(
      _snapshot.copyWith(
        sessionState: RealtimeSessionState.stopping,
        microphoneActive: false,
      ),
    );
  }

  Future<void> _completeNaturally(int operationId) async {
    if (!_guard.isCurrent(operationId) || _naturalCompletionRunning) {
      return;
    }
    _naturalCompletionRunning = true;
    await _stopCapture();
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
    await audioSession.deactivate();
    _session?.sendSessionEnd();
    _taskLauncher.terminateBestEffort();
    await _eventSubscription?.cancel();
    await _session?.close();
    await recorder.dispose();
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
