import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
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
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';

final class TextToSpeechViewModel extends BaseViewModel<TextToSpeechState> {
  TextToSpeechViewModel({
    required this.audioSession,
    required this.apiClient,
    required this.sessionFactory,
    required this.player,
    required this.sessionGuard,
    this.terminalTimeout = const Duration(seconds: 3),
  }) : parameters = ModelParameterValues(
         WiroModelCatalog.mossTtsRealtime.firstPassFields,
       ),
       super(const TextToSpeechState()) {
    _playerFailureSubscription = player.failures.listen(
      _handlePlayerFailure,
    );
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
  final PcmAudioPlayer player;
  final RealtimeSessionGuard sessionGuard;
  final Duration terminalTimeout;
  ModelParameterValues parameters;

  static const int _maximumProtocolEvents = 40;

  late final StreamSubscription<AudioPlaybackFailure>
  _playerFailureSubscription;
  late final StreamSubscription<RealtimeAudioInterruption>
  _interruptionSubscription;
  late final StreamSubscription<void> _becomingNoisySubscription;
  late final StreamSubscription<void> _routeSubscription;
  RealtimeSessionLease? _sessionLease;
  WiroRunResult? _runResult;
  WiroRequestCancellation? _runCancellation;
  RealtimeSessionClient? _session;
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  Completer<void>? _terminalCompleter;
  Future<void>? _playbackCompletion;
  Future<void>? _naturalCompletion;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  Timer? _elapsedTimer;
  Stopwatch? _stopwatch;
  int _operationId = 0;
  bool _disposed = false;
  bool _naturalCompletionRunning = false;

  ValueNotifier<String> get promptNotifier {
    final mossText = parameters.notifiers['text'];
    if (mossText != null) {
      return mossText;
    }
    return parameters.require('prompt');
  }

  void selectModel(ModelDefinition model) {
    if (state.sessionState.isActive ||
        model.direction != RealtimeDirection.textToSpeech) {
      return;
    }
    parameters.dispose();
    parameters = ModelParameterValues(model.firstPassFields);
    emit(
      state.copyWith(
        selectedModel: model,
        errorMessage: null,
      ),
    );
  }

  Future<void> start() {
    if (!state.sessionState.canStart) {
      return Future<void>.value();
    }
    final prompt = promptNotifier.value.trim();
    if (prompt.isEmpty) {
      emit(
        state.copyWith(
          status: ViewStatus.error,
          sessionState: RealtimeSessionState.failure,
          errorMessage: 'Enter text to synthesize.',
        ),
      );
      return Future<void>.value();
    }
    final lease = sessionGuard.acquire(RealtimeSessionOwner.speech);
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
    final operation = _start(prompt);
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
  }

  Future<void> _start(String prompt) async {
    final operationId = ++_operationId;
    emit(
      state.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.preparingAudio,
        elapsed: Duration.zero,
        isPlaying: false,
        errorMessage: null,
        protocolEvents: const [],
      ),
    );

    try {
      final preparation = await audioSession.prepare(
        RealtimeAudioProfile.speech,
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

      final cancellation = apiClient.createCancellation();
      _runCancellation = cancellation;
      emit(
        state.copyWith(
          sessionState: RealtimeSessionState.creatingTask,
        ),
      );
      final request = parameters.requestSnapshot();
      request[_promptFieldId] = prompt;
      final runResult = await apiClient.runModel(
        model: state.selectedModel,
        parameters: request,
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
      _playbackCompletion = null;
      _naturalCompletion = null;
      _naturalCompletionRunning = false;
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

      await player.start();
      if (!_isCurrent(operationId)) {
        await player.stop();
        await session.close();
        return;
      }
      _startElapsedTimer(operationId);
      emit(
        state.copyWith(
          status: ViewStatus.success,
          sessionState: RealtimeSessionState.streaming,
          protocolEvents: _withProtocolEvent(
            state.protocolEvents,
            'playback_stream_started',
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
        isPlaying: false,
      ),
    );

    _runCancellation?.cancel();
    _runCancellation = null;
    _stopElapsedTimer();
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
    _playbackCompletion = null;
    _naturalCompletion = null;
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
        isPlaying: false,
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
      case RealtimeBinaryEvent():
        _queueAudio(event, operationId);
      case RealtimeStatusEvent(
        type: RealtimeEventType.streamEnded,
      ):
        _appendProtocolEvent(event.wireType);
        emit(
          state.copyWith(
            sessionState: RealtimeSessionState.stopping,
          ),
        );
        _playbackCompletion ??= _finishPlayback(operationId);
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
      case RealtimeOutputEvent():
      case RealtimeStatusEvent():
      case RealtimeUnknownEvent():
        _appendProtocolEvent(event.wireType);
    }
  }

  void _queueAudio(RealtimeBinaryEvent event, int operationId) {
    if (!state.isPlaying) {
      emit(state.copyWith(isPlaying: true));
    }
    if (_isCurrent(operationId) && !player.tryEnqueue(event.bytes)) {
      _appendProtocolEvent('audio_chunk_dropped');
    }
  }

  Future<void> _finishPlayback(int operationId) async {
    if (!_isCurrent(operationId)) {
      return;
    }
    await player.complete();
    if (_isCurrent(operationId)) {
      emit(state.copyWith(isPlaying: false));
    }
  }

  Future<void> _completeNaturally(int operationId) async {
    if (!_isCurrent(operationId) || _naturalCompletionRunning) {
      return;
    }
    _naturalCompletionRunning = true;
    _playbackCompletion ??= _finishPlayback(operationId);
    await _playbackCompletion;
    if (!_isCurrent(operationId)) {
      _naturalCompletionRunning = false;
      return;
    }
    final completionId = ++_operationId;
    _stopElapsedTimer();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _playbackCompletion = null;
    _naturalCompletion = null;
    _naturalCompletionRunning = false;
    _runResult = null;
    _releaseLease();
    if (!_isCurrent(completionId)) {
      return;
    }
    emit(
      state.copyWith(
        status: ViewStatus.success,
        sessionState: RealtimeSessionState.completed,
        isPlaying: false,
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

  void _handlePlayerFailure(AudioPlaybackFailure failure) {
    if (state.sessionState.isActive) {
      unawaited(_fail(_operationId, failure));
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
    await player.stop();
    await audioSession.deactivate();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _session?.close();
    _session = null;
    _terminalCompleter = null;
    _playbackCompletion = null;
    _naturalCompletionRunning = false;
    _releaseLease();
    if (!_isCurrent(failureId)) {
      return;
    }
    emit(
      state.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        isPlaying: false,
        errorMessage: _failureMessage(error),
        protocolExpanded: true,
        protocolEvents: _withProtocolEvent(
          state.protocolEvents,
          'failure:${_failureCode(error)}',
        ),
      ),
    );
  }

  Future<void> _disposeResources() async {
    await _playerFailureSubscription.cancel();
    await _interruptionSubscription.cancel();
    await _becomingNoisySubscription.cancel();
    await _routeSubscription.cancel();
    await player.stop();
    await audioSession.deactivate();
    _session?.sendSessionEnd();
    _terminateTaskBestEffort();
    await _eventSubscription?.cancel();
    await _session?.close();
    await player.dispose();
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

  String get _promptFieldId {
    return state.selectedModel.modelSlug ==
            WiroModelCatalog.mossTtsRealtime.modelSlug
        ? 'text'
        : 'prompt';
  }

  String _failureMessage(Object error) {
    return switch (error) {
      WiroFailure() => error.message,
      AudioFailure() => error.message,
      _ => 'The speech session could not be completed.',
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
