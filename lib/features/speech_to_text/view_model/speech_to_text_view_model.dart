import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

final class SpeechToTextViewModel extends BaseViewModel<SpeechToTextState> {
  SpeechToTextViewModel({
    required this.audioSession,
    required this.apiClient,
    required this.sessionFactory,
    required this.recorder,
    required this.sessionGuard,
    this.terminalTimeout = const Duration(seconds: 3),
  }) : parameters = ModelParameterValues(
         WiroModelCatalog.voxtralMiniRealtime.firstPassFields,
       ),
       super(const SpeechToTextState()) {
    _interruptionSubscription = audioSession.interruptions.listen(
      _handleInterruption,
    );
    _becomingNoisySubscription = audioSession.becomingNoisy.listen(
      (_) => _stopForAudioRouteSafety(),
    );
    _routeSubscription = audioSession.routeChanges.listen(
      (_) => _handleRouteChange(),
    );
  }

  final RealtimeAudioSession audioSession;
  final WiroApiClient apiClient;
  final RealtimeSessionFactory sessionFactory;
  final PcmAudioRecorder recorder;
  final RealtimeSessionGuard sessionGuard;
  final Duration terminalTimeout;
  final ModelParameterValues parameters;

  static const String _transcriptPrefix = 'TRANSCRIPT_USER:';
  static const int _maximumProtocolEvents = 40;

  WiroRequestCancellation? _runCancellation;
  late final StreamSubscription<RealtimeAudioInterruption>
  _interruptionSubscription;
  late final StreamSubscription<void> _becomingNoisySubscription;
  late final StreamSubscription<void> _routeSubscription;
  RealtimeSessionLease? _sessionLease;
  WiroRunResult? _runResult;
  RealtimeSessionClient? _session;
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  StreamSubscription<Uint8List>? _pcmSubscription;
  Completer<void>? _terminalCompleter;
  Timer? _elapsedTimer;
  Stopwatch? _stopwatch;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  int _operationId = 0;
  bool _disposed = false;

  Future<void> start() {
    if (!state.sessionState.canStart) {
      return Future<void>.value();
    }
    final lease = sessionGuard.acquire(
      RealtimeSessionOwner.transcription,
    );
    if (lease == null) {
      emit(
        state.copyWith(
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
    final operationId = ++_operationId;
    emit(
      state.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.requestingPermission,
        elapsed: Duration.zero,
        transcript: '',
        microphoneActive: false,
        errorMessage: null,
        protocolEvents: const [],
      ),
    );

    try {
      final preparation = await audioSession.prepare(
        RealtimeAudioProfile.transcription,
      );
      if (!_isCurrent(operationId)) {
        await audioSession.deactivate();
        return;
      }
      if (preparation != AudioPreparationResult.ready) {
        await audioSession.deactivate();
        _releaseLease();
        emit(
          state.copyWith(
            status: ViewStatus.error,
            sessionState: RealtimeSessionState.failure,
            errorMessage: preparation.errorMessage,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          sessionState: RealtimeSessionState.preparingAudio,
        ),
      );
      final cancellation = apiClient.createCancellation();
      _runCancellation = cancellation;
      emit(
        state.copyWith(
          sessionState: RealtimeSessionState.creatingTask,
        ),
      );
      final runResult = await apiClient.runModel(
        model: state.selectedModel,
        parameters: parameters.requestSnapshot(),
        cancellation: cancellation,
      );
      if (!_isCurrent(operationId)) {
        unawaited(
          apiClient.terminateTaskBestEffort(
            taskId: runResult.taskId,
            taskToken: runResult.taskToken,
          ),
        );
        return;
      }
      _runResult = runResult;
      _runCancellation = null;

      final session = sessionFactory(
        taskId: runResult.taskId,
        taskToken: runResult.taskToken,
      );
      _session = session;
      _terminalCompleter = Completer<void>();
      _eventSubscription = session.events.listen(
        (event) => _handleEvent(event, operationId),
        onError: (Object error) => _handleEventError(error, operationId),
        onDone: () => _handleEventStreamDone(operationId),
      );
      emit(
        state.copyWith(
          sessionState: RealtimeSessionState.connectingSocket,
        ),
      );
      final connection = session.connect();
      await Future<void>.delayed(Duration.zero);
      if (_isCurrent(operationId)) {
        emit(
          state.copyWith(
            sessionState: RealtimeSessionState.waitingForStream,
          ),
        );
      }
      await connection;
      if (!_isCurrent(operationId)) {
        await session.close();
        return;
      }

      final pcmStream = await recorder.start(
        PcmCaptureProfile.transcription,
      );
      if (!_isCurrent(operationId)) {
        await recorder.stop();
        await session.close();
        return;
      }
      _pcmSubscription = pcmStream.listen(
        (chunk) => _sendPcm(chunk, operationId),
        onError: (Object error) => _handleAudioError(error, operationId),
      );
      _startElapsedTimer(operationId);
      emit(
        state.copyWith(
          status: ViewStatus.success,
          sessionState: RealtimeSessionState.streaming,
          microphoneActive: true,
          protocolEvents: _withProtocolEvent(
            state.protocolEvents,
            'microphone_stream_started',
          ),
        ),
      );
    } on Object catch (error) {
      if (_isCurrent(operationId)) {
        await _fail(operationId, error);
      }
    }
  }

  Future<void> stop() {
    final pendingStop = _stopOperation;
    if (pendingStop != null) {
      return pendingStop;
    }
    if (!state.sessionState.canStop) {
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
    final operationId = ++_operationId;
    emit(
      state.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.stopping,
        microphoneActive: false,
      ),
    );

    _runCancellation?.cancel();
    _runCancellation = null;
    _stopElapsedTimer();
    await _stopCapture();
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
    _runResult = null;
    _releaseLease();

    if (!_isCurrent(operationId)) {
      return;
    }
    emit(
      state.copyWith(
        status: shutdownTimedOut ? ViewStatus.error : ViewStatus.success,
        sessionState: shutdownTimedOut
            ? RealtimeSessionState.failure
            : RealtimeSessionState.completed,
        microphoneActive: false,
        errorMessage: shutdownTimedOut
            ? const WiroShutdownTimeoutFailure().message
            : null,
        protocolEvents: _withProtocolEvent(
          state.protocolEvents,
          shutdownTimedOut ? 'shutdown_timeout' : 'session_stopped',
        ),
      ),
    );
  }

  void clearTranscript() {
    if (state.sessionState.isActive) {
      return;
    }
    emit(state.copyWith(transcript: ''));
  }

  void toggleProtocolPanel() {
    emit(state.copyWith(protocolExpanded: !state.protocolExpanded));
  }

  @override
  void dispose() {
    _disposed = true;
    _operationId++;
    _runCancellation?.cancel();
    _stopElapsedTimer();
    unawaited(_disposeResources());
    parameters.dispose();
    super.dispose();
  }

  void _sendPcm(Uint8List chunk, int operationId) {
    if (!_isCurrent(operationId)) {
      return;
    }
    try {
      final sent = _session?.sendAudio(chunk) ?? false;
      if (!sent) {
        unawaited(
          _fail(operationId, const WiroSocketFailure()),
        );
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
    if (!_isCurrent(operationId)) {
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
        unawaited(_completeNaturally(operationId));
      case RealtimeErrorEvent():
        _appendProtocolEvent(event.wireType);
        unawaited(_fail(operationId, const WiroSocketFailure()));
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
    emit(
      state.copyWith(
        transcript: message.substring(_transcriptPrefix.length),
        protocolEvents: _withProtocolEvent(
          state.protocolEvents,
          event.wireType,
        ),
      ),
    );
  }

  Future<void> _handleStreamEnded(int operationId) async {
    await _stopCapture();
    await audioSession.deactivate();
    if (!_isCurrent(operationId)) {
      return;
    }
    emit(
      state.copyWith(
        sessionState: RealtimeSessionState.stopping,
        microphoneActive: false,
      ),
    );
  }

  Future<void> _completeNaturally(int operationId) async {
    if (!_isCurrent(operationId)) {
      return;
    }
    final completionId = ++_operationId;
    _stopElapsedTimer();
    await _stopCapture();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _runResult = null;
    _releaseLease();
    if (!_isCurrent(completionId)) {
      return;
    }
    emit(
      state.copyWith(
        status: ViewStatus.success,
        sessionState: RealtimeSessionState.completed,
        microphoneActive: false,
      ),
    );
  }

  void _handleEventError(Object error, int operationId) {
    if (_isCurrent(operationId)) {
      unawaited(_fail(operationId, error));
    }
  }

  void _handleEventStreamDone(int operationId) {
    final terminalReceived = _terminalCompleter?.isCompleted ?? false;
    if (_isCurrent(operationId) && !terminalReceived) {
      unawaited(_fail(operationId, const WiroSocketFailure()));
    }
  }

  void _handleAudioError(Object error, int operationId) {
    if (_isCurrent(operationId)) {
      unawaited(_fail(operationId, error));
    }
  }

  Future<void> _fail(int operationId, Object error) async {
    if (!_isCurrent(operationId)) {
      return;
    }
    final failureId = ++_operationId;
    _terminateTaskBestEffort();
    _runCancellation?.cancel();
    _runCancellation = null;
    _stopElapsedTimer();
    await _stopCapture();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _releaseLease();
    if (!_isCurrent(failureId)) {
      return;
    }
    emit(
      state.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        microphoneActive: false,
        errorMessage: _failureMessage(error),
        protocolExpanded: true,
        protocolEvents: _withProtocolEvent(
          state.protocolEvents,
          'failure:${_failureCode(error)}',
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
    await _interruptionSubscription.cancel();
    await _becomingNoisySubscription.cancel();
    await _routeSubscription.cancel();
    await _stopCapture();
    await audioSession.deactivate();
    _session?.sendSessionEnd();
    _terminateTaskBestEffort();
    await _eventSubscription?.cancel();
    await _session?.close();
    await recorder.dispose();
    _releaseLease();
  }

  void _handleInterruption(RealtimeAudioInterruption interruption) {
    if (interruption == RealtimeAudioInterruption.began) {
      _stopForAudioRouteSafety();
    }
  }

  void _stopForAudioRouteSafety() {
    if (state.sessionState.canStop) {
      unawaited(stop());
    }
  }

  void _handleRouteChange() {
    if (state.sessionState.isActive) {
      _appendProtocolEvent('audio_route_changed');
    }
  }

  void _releaseLease() {
    final lease = _sessionLease;
    _sessionLease = null;
    sessionGuard.release(lease);
  }

  void _terminateTaskBestEffort() {
    final runResult = _runResult;
    _runResult = null;
    if (runResult != null) {
      unawaited(
        apiClient.terminateTaskBestEffort(
          taskId: runResult.taskId,
          taskToken: runResult.taskToken,
        ),
      );
    }
  }

  void _startElapsedTimer(int operationId) {
    _stopwatch = Stopwatch()..start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isCurrent(operationId)) {
        emit(
          state.copyWith(
            elapsed: _stopwatch?.elapsed ?? Duration.zero,
          ),
        );
      }
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _stopwatch?.stop();
    _stopwatch = null;
  }

  void _appendProtocolEvent(String event) {
    emit(
      state.copyWith(
        protocolEvents: _withProtocolEvent(
          state.protocolEvents,
          event,
        ),
      ),
    );
  }

  List<String> _withProtocolEvent(
    List<String> events,
    String event,
  ) {
    final retained = events.length >= _maximumProtocolEvents
        ? events.sublist(events.length - _maximumProtocolEvents + 1)
        : events;
    return [...retained, event];
  }

  void _completeTerminalWait() {
    final terminal = _terminalCompleter;
    if (terminal != null && !terminal.isCompleted) {
      terminal.complete();
    }
  }

  String _failureMessage(Object error) {
    return switch (error) {
      WiroFailure() => error.message,
      AudioFailure() => error.message,
      _ => 'The transcription session could not be completed.',
    };
  }

  String _failureCode(Object error) {
    return switch (error) {
      WiroFailure() => error.code.name,
      AudioFailure() => error.code.name,
      _ => 'unknown',
    };
  }

  bool _isCurrent(int operationId) {
    return !_disposed && operationId == _operationId;
  }
}
