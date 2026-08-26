import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/app/config/conversation_config.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_route_watcher.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
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
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_barge_in.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_mic_pipeline.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_playback_coordinator.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_transcript_parser.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';

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
    this.model = ConversationConfig.model,
    String persona = ConversationConfig.persona,
    String voice = ConversationConfig.voice,
    this.maxSessionDuration = ConversationConfig.maxSessionDuration,
    this.suspendGracePeriod = ConversationConfig.suspendGracePeriod,
    this.reconnectTimeout = const Duration(seconds: 4),
    this.terminalTimeout = const Duration(seconds: 3),
    this.maxRetryAttempts = 5,
    this.retryBaseDelay = const Duration(milliseconds: 500),
    this.micStallTimeout = const Duration(seconds: 3),
    this.autoRestartDelay = const Duration(seconds: 5),
    this.maxAutoRestarts = 2,
    this.interruptHoldTimeout = const Duration(milliseconds: 900),
    this.interruptHoldCooldown = const Duration(milliseconds: 1500),
    this.noiseGate,
  }) : parameters = ModelParameterValues(
         model.firstPassFields,
         overrides: {
           'system_instructions': persona,
           'voice': voice,
         },
       ) {
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
  final int maxRetryAttempts;
  final Duration retryBaseDelay;

  /// How long the live microphone may deliver nothing at all before the
  /// capture pipeline counts as dead.
  ///
  /// Healthy capture produces fifty chunks a second no matter how quiet
  /// the room is, so a few silent seconds can only mean the pipeline broke
  /// — a hot restart with a stale native engine, a revoked input route —
  /// and the session heals itself through the ordinary retry path.
  final Duration micStallTimeout;

  /// How long a recoverable failure rests before the conversation restarts
  /// itself from scratch.
  ///
  /// Reaching the failure state means the retry budget ran out, yet the
  /// user relaunching the app proves a fresh start usually works — so the
  /// page performs that fresh start on its own instead of stranding the
  /// user on an error screen. The delay doubles on each consecutive
  /// failure (capped at four times the base) so a persistently broken
  /// backend is not hammered with new tasks.
  final Duration autoRestartDelay;

  /// How many consecutive restarts may run before the orb is handed back.
  ///
  /// A restart that reaches a live conversation clears the count, so the
  /// budget only runs down while nothing is working. Once it does, the
  /// screen stops cycling through connect attempts nobody asked for and
  /// waits to be tapped: a speaker looking at an orb that is trying and
  /// failing on its own cannot tell it from one that is listening.
  final int maxAutoRestarts;

  /// How long a suspected interruption may stay unresolved before the held
  /// audio plays on from where it was silenced.
  ///
  /// A hold that neither confirms as speech nor drains to silence within
  /// this window is ambiguous ongoing noise — steady typing, most often —
  /// and the answer is worth more than the ambiguity.
  final Duration interruptHoldTimeout;

  /// How long new holds rest after one proved to be noise, so a typing
  /// session cannot stutter playback with a hold per keystroke. Sustained
  /// speech still cuts through during the rest: only the instant-pause
  /// stage is suppressed, never the confirmed interruption.
  final Duration interruptHoldCooldown;

  /// Optional gate that silences steady background sound — a television,
  /// traffic — before microphone audio reaches the model. Null sends the
  /// microphone through untouched.
  final PcmNoiseGate? noiseGate;

  /// How long one conversation may run before it ends itself, or
  /// [Duration.zero] for no ceiling.
  /// See [ConversationConfig.maxSessionDuration].
  final Duration maxSessionDuration;

  /// How long a suspended conversation is held for a speaker who left the
  /// screen, or [Duration.zero] to end it immediately instead.
  /// See [ConversationConfig.suspendGracePeriod].
  final Duration suspendGracePeriod;

  /// How long a reconnect may spend finding out whether the held task is
  /// still there.
  ///
  /// A task the server already tore down can still accept a socket and then
  /// simply never open a stream, so the ordinary ready timeout would spend
  /// its full patience on a task that is never coming back. Recovery is the
  /// point here, and starting a new task is always available.
  final Duration reconnectTimeout;

  @override
  final RealtimeSessionGuard sessionGuard;

  @override
  final ModelDefinition model;

  @override
  final ModelParameterValues parameters;

  @override
  final ConversationVoiceActivity voiceActivity = ConversationVoiceActivity();

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
  late final ConversationBargeIn _bargeIn = ConversationBargeIn(
    playback: _playbackCoordinator,
    voiceActivity: voiceActivity,
    onProtocolEvent: _appendProtocolEvent,
    holdTimeout: interruptHoldTimeout,
    holdCooldown: interruptHoldCooldown,
  );
  late final ConversationMicPipeline _micPipeline = ConversationMicPipeline(
    onStall: _handleMicStall,
    noiseGate: noiseGate,
    stallTimeout: micStallTimeout,
  );
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
  Future<void>? _relaunchOperation;
  Timer? _autoRestartTimer;
  int _watchdogOperationId = 0;
  Timer? _graceTimer;
  DateTime? _suspendedAt;
  int _autoRestartCycle = 0;
  bool _naturalCompletionRunning = false;
  int _retryAttempt = 0;

  /// The parameter values the live task was created with.
  ///
  /// Parameters are only read while a task is being created, so editing them
  /// mid-conversation changes nothing until the session is rebuilt. Keeping
  /// what was actually sent is what lets [applyParameterChanges] tell an
  /// edited form from an untouched one.
  Map<String, String> _launchedParameters = const {};

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
    _cancelAutoRestart();
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
    _retryAttempt = 0;
    final operation = _start(isRetry: false);
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
  }

  Future<void> _start({required bool isRetry}) async {
    final operationId = _guard.begin();
    if (!isRetry) {
      _protocolLog.clear();
    }
    // An automatic reconnect keeps what was already said; only a fresh
    // conversation starts from a blank transcript and a zeroed clock.
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.requestingPermission,
        elapsed: isRetry ? null : Duration.zero,
        userTranscript: isRetry ? null : '',
        aiTranscript: isRetry ? null : '',
        microphoneActive: false,
        errorMessage: null,
        canOpenSystemSettings: false,
        protocolEvents: _protocolLog.events,
      ),
    );

    try {
      if (!await _prepareAudio(operationId)) {
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
      final runResult = await _launchTask(operationId);
      if (runResult == null) {
        return;
      }

      final connected = await _openSession(runResult, operationId);
      if (!connected) {
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
        await _session?.close();
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
      _startMicWatchdog(operationId);
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
    _micPipeline.stopWatchdog();
    _cancelAutoRestart();
    _bargeIn.cancelHold();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.stopping,
        isReconfiguring: false,
        microphoneActive: false,
      ),
    );

    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    await _stopCapture();
    await player.stop();
    _playbackCoordinator.reset();
    voiceActivity.reset();
    noiseGate?.reset();
    await _naturalCompletion;
    await audioSession.deactivate();

    var shutdownTimedOut = false;
    var endedCleanly = false;
    final session = _session;
    if (session != null && !session.isClosed) {
      endedCleanly = true;
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
    // A session end tells the server to wind the task down; without one —
    // a held conversation whose speaker never came back — nothing has, and
    // forgetting the task would leave it billing on its own.
    if (endedCleanly) {
      _taskLauncher.release();
    } else {
      _taskLauncher.terminateBestEffort();
    }
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
        isSuspended: false,
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
  Future<void> changeVoice(String voice) {
    if (_guard.isDisposed) {
      return Future<void>.value();
    }
    if (!_snapshot.sessionState.isActive || _snapshot.isReconfiguring) {
      return _relaunchOperation ?? Future<void>.value();
    }
    final currentVoice = parameters.require('voice').value;
    if (currentVoice == voice) {
      return Future<void>.value();
    }
    parameters.require('voice').value = voice;
    return _runRelaunch('voice_change');
  }

  @override
  Future<void> applyParameterChanges() {
    if (_guard.isDisposed) {
      return Future<void>.value();
    }
    final pending = _relaunchOperation;
    if (pending != null) {
      return pending;
    }
    // An idle session reads the edited values by itself the next time it
    // creates a task; only a live one has to be rebuilt to notice them.
    if (!_snapshot.sessionState.isActive) {
      return Future<void>.value();
    }
    if (mapEquals(parameters.snapshot(), _launchedParameters)) {
      return Future<void>.value();
    }
    return _runRelaunch('settings_change');
  }

  @override
  Future<void> suspend() async {
    if (_guard.isDisposed ||
        _snapshot.isSuspended ||
        !_snapshot.sessionState.isActive) {
      return;
    }
    // Half a handshake is not something worth coming back to, and a
    // configured zero says the speaker leaving is the same as hanging up.
    if (suspendGracePeriod <= Duration.zero ||
        _startOperation != null ||
        _relaunchOperation != null) {
      await stop();
      return;
    }
    final operationId = _guard.begin();
    _micPipeline.stopWatchdog();
    _cancelAutoRestart();
    _bargeIn.cancelHold();
    _elapsedClock.stop();
    _taskLauncher.cancelPendingRequest();
    await _stopCapture();
    player.flush();
    await player.stop();
    _playbackCoordinator.reset();
    voiceActivity.reset();
    noiseGate?.reset();
    await audioSession.deactivate();
    await _dropSocket();
    if (!_guard.isCurrent(operationId)) {
      return;
    }
    // Whoever is on screen now should be able to use the microphone; the
    // task is what is being held, not the hardware.
    _releaseLease();
    _suspendedAt = DateTime.now();
    _graceTimer = Timer(suspendGracePeriod, _expireHold);
    _publish(
      _snapshot.copyWith(
        isSuspended: true,
        microphoneActive: false,
        protocolEvents: _protocolLog.add('conversation_held'),
      ),
    );
  }

  @override
  Future<void> resume() async {
    if (_guard.isDisposed || !_snapshot.isSuspended) {
      return;
    }
    _cancelGraceTimer();
    // A frozen app runs no timers, so a hold can outlive its own deadline.
    // The clock decides whether the speaker is still expected, not the
    // timer that may never have fired.
    final suspendedAt = _suspendedAt;
    if (suspendedAt == null ||
        DateTime.now().difference(suspendedAt) > suspendGracePeriod) {
      await _endHeldSession('hold_expired');
      return;
    }
    final lease = sessionGuard.acquire(RealtimeSessionOwner.conversation);
    if (lease == null) {
      await _endHeldSession('hold_lost_to_another_session');
      return;
    }
    _sessionLease = lease;
    _suspendedAt = null;
    await _runRelaunch('resume', reuseTask: true, prepareAudio: true);
  }

  void _expireHold() {
    _graceTimer = null;
    if (_guard.isDisposed || !_snapshot.isSuspended) {
      return;
    }
    unawaited(_endHeldSession('hold_expired'));
  }

  Future<void> _endHeldSession(String reason) async {
    _suspendedAt = null;
    _appendProtocolEvent(reason);
    await stop();
  }

  void _cancelGraceTimer() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  Future<void> _runRelaunch(
    String reason, {
    bool reuseTask = false,
    bool prepareAudio = false,
  }) {
    final operation = _relaunch(
      reason,
      reuseTask: reuseTask,
      prepareAudio: prepareAudio,
    );
    _relaunchOperation = operation;
    return operation.whenComplete(() {
      if (identical(_relaunchOperation, operation)) {
        _relaunchOperation = null;
      }
    });
  }

  /// Rebuilds the live conversation in place, keeping the transcript and the
  /// clock as they are.
  ///
  /// With [reuseTask] the held task is dialled back into rather than replaced,
  /// which is what keeps the assistant's memory across a dropped socket; a
  /// refused reconnect falls through to a new task on its own. Edited
  /// parameters cannot reuse anything, since they are only read while a task
  /// is being created. [prepareAudio] re-acquires the audio route for callers
  /// that let go of it, such as a failure or a return from the background.
  Future<void> _relaunch(
    String reason, {
    required bool reuseTask,
    required bool prepareAudio,
  }) async {
    final operationId = _guard.begin();
    final preservedUserTranscript = _snapshot.userTranscript;
    final preservedAiTranscript = _snapshot.aiTranscript;
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.loading,
        sessionState: RealtimeSessionState.creatingTask,
        isReconfiguring: true,
        isSuspended: false,
        microphoneActive: false,
        protocolEvents: _protocolLog.add('${reason}_started'),
      ),
    );

    try {
      await _stopCapture();
      _bargeIn.cancelHold();
      player.flush();
      _playbackCoordinator.reset();
      voiceActivity.reset();
      noiseGate?.reset();

      if (prepareAudio && !await _prepareAudio(operationId)) {
        return;
      }

      final reconnected =
          reuseTask &&
          await _reconnectToHeldTask(
            operationId,
            userTranscript: preservedUserTranscript,
            aiTranscript: preservedAiTranscript,
          );
      if (!_guard.isCurrent(operationId)) {
        return;
      }

      if (!reconnected) {
        await _closeActiveSessionForRelaunch();
        if (!_guard.isCurrent(operationId)) {
          return;
        }
        final runResult = await _launchTask(operationId);
        if (runResult == null) {
          return;
        }
        final connected = await _openSession(
          runResult,
          operationId,
          userTranscript: preservedUserTranscript,
          aiTranscript: preservedAiTranscript,
        );
        if (!connected) {
          return;
        }
      }

      final pcmStream = await recorder.start(PcmCaptureProfile.conversation);
      if (!_guard.isCurrent(operationId)) {
        await recorder.stop();
        await _session?.close();
        return;
      }
      if (!player.isPlaying) {
        await player.start();
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
          isReconfiguring: false,
          microphoneActive: !_snapshot.muted,
          protocolEvents: _protocolLog.add('${reason}_completed'),
        ),
      );
      _startMicWatchdog(operationId);
    } on Object catch (error) {
      if (_guard.isCurrent(operationId)) {
        await _fail(operationId, error);
      }
    }
  }

  /// Creates the task and records the values it was created with, so a later
  /// edit of the same form can be recognised as a real change.
  Future<WiroRunResult?> _launchTask(int operationId) async {
    final requested = parameters.snapshot();
    final runResult = await _taskLauncher.launch(
      model: model,
      parameters: parameters.requestSnapshot(),
      isStillWanted: () => _guard.isCurrent(operationId),
    );
    if (runResult == null) {
      return null;
    }
    _launchedParameters = requested;
    return runResult;
  }

  /// Subscribes to [runResult]'s task and waits for its stream to open.
  ///
  /// Returns false when something newer superseded the caller while the
  /// socket was connecting, in which case the half-built session is already
  /// closed.
  Future<bool> _openSession(
    WiroRunResult runResult,
    int operationId, {
    String? userTranscript,
    String? aiTranscript,
  }) async {
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
        userTranscript: userTranscript,
        aiTranscript: aiTranscript,
      ),
    );
    final connection = session.connect();
    // The state below advances before the connect future is awaited, and a
    // subscription the server refuses outright fails inside that gap. An
    // unwatched future would report that as an unhandled error and take the
    // whole zone down, so the listener is attached up front.
    unawaited(connection.then((_) {}, onError: (Object _) {}));
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
      return false;
    }
    return true;
  }

  /// Claims the audio route, reporting the refusal and letting go of the
  /// lease when it is denied. False means the caller must give up.
  Future<bool> _prepareAudio(int operationId) async {
    final preparation = await audioSession.prepare(
      RealtimeAudioProfile.conversation,
    );
    if (!_guard.isCurrent(operationId)) {
      await audioSession.deactivate();
      return false;
    }
    if (preparation == AudioPreparationResult.ready) {
      return true;
    }
    await audioSession.deactivate();
    _releaseLease();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        isReconfiguring: false,
        isSuspended: false,
        microphoneActive: false,
        errorMessage: preparation.errorMessage,
        canOpenSystemSettings: preparation.needsSystemSettings,
      ),
    );
    return false;
  }

  /// Dials back into the task the launcher is still holding.
  ///
  /// A socket dies for reasons the task never hears about — a changed
  /// network, a phone that dozed off — and the task keeps its side of the
  /// conversation meanwhile. Reconnecting therefore costs one subscription
  /// instead of one launch, and it is the only thing that lets the assistant
  /// remember what was said before the drop; a new task starts a stranger.
  ///
  /// Whether the task survived is the server's decision, so a refusal is an
  /// ordinary outcome rather than a failure: false asks the caller to launch
  /// a new task instead.
  Future<bool> _reconnectToHeldTask(
    int operationId, {
    required String userTranscript,
    required String aiTranscript,
  }) async {
    final heldTask = _taskLauncher.runResult;
    if (heldTask == null) {
      return false;
    }
    _taskLauncher.cancelPendingRequest();
    await _dropSocket();
    if (!_guard.isCurrent(operationId)) {
      return false;
    }
    _appendProtocolEvent('reconnect_attempted');
    try {
      final reconnected = await _openSession(
        heldTask,
        operationId,
        userTranscript: userTranscript,
        aiTranscript: aiTranscript,
      ).timeout(reconnectTimeout);
      if (reconnected) {
        _appendProtocolEvent('reconnect_accepted');
      }
      return reconnected;
    } on Object {
      _appendProtocolEvent('reconnect_refused');
      await _dropSocket();
      return false;
    }
  }

  /// Lets go of the socket without telling the server anything, so the task
  /// on the other end stays alive and reconnectable.
  ///
  /// The event subscription goes first: a cancelled listener cannot turn the
  /// close into the remote hang-up that would tear the task down.
  Future<void> _dropSocket() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    final session = _session;
    _session = null;
    _terminalCompleter = null;
    _naturalCompletion = null;
    _naturalCompletionRunning = false;
    await session?.close();
  }

  Future<void> _closeActiveSessionForRelaunch() async {
    _taskLauncher.cancelPendingRequest();
    final session = _session;
    if (session != null && !session.isClosed) {
      session.sendSessionEnd();
    }
    await _dropSocket();
    _taskLauncher.terminateBestEffort();
  }

  @override
  void setMuted({required bool muted}) {
    if (_guard.isDisposed) {
      return;
    }
    recorder.setMuted(muted: muted);
    if (muted) {
      voiceActivity.resetUser();
    }
    _publish(
      _snapshot.copyWith(
        muted: muted,
        microphoneActive:
            _snapshot.sessionState == RealtimeSessionState.streaming && !muted,
      ),
    );
  }

  @override
  void interruptAssistant() {
    if (_guard.isDisposed ||
        _snapshot.sessionState != RealtimeSessionState.streaming) {
      return;
    }
    // Without pending audio there is nothing to silence, and interrupting
    // anyway would latch the coordinator against the next answer.
    if (!voiceActivity.aiAudioPending) {
      return;
    }
    if (_playbackCoordinator.interruptTurn()) {
      _bargeIn.cancelHold();
      voiceActivity.resetAi();
      _appendProtocolEvent('assistant_silenced_by_user');
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (_guard.isDisposed) {
      return;
    }
    final opened = await audioSession.openSystemSettings();
    if (!opened) {
      _appendProtocolEvent('system_settings_unavailable');
    }
  }

  @override
  Future<void> dispose() async {
    _guard.dispose();
    _micPipeline.dispose();
    _cancelAutoRestart();
    _cancelGraceTimer();
    _bargeIn.dispose();
    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    parameters.dispose();
    await _disposeResources();
    voiceActivity.dispose();
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
    final processed = _micPipeline.process(
      chunk,
      assistantAudible: voiceActivity.aiAudioPending,
    );
    try {
      final sent = _session?.sendAudio(processed.gated) ?? false;
      if (!sent) {
        unawaited(_fail(operationId, const WiroSocketFailure()));
        return;
      }
      // Only a microphone chunk that actually reached the server proves
      // the rebuilt pipeline healthy; resetting the retry budget any
      // earlier would let a dead microphone reconnect forever.
      _retryAttempt = 0;
      _autoRestartCycle = 0;
      // The orb and barge-in listen to the gated signal too, so the
      // television can neither light the waveform nor cut the assistant.
      voiceActivity.addUserChunk(processed.gated, level: processed.level);
      _bargeIn.evaluate();
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
      // Wiro documents task_error as interim stderr that a task can still
      // recover from, and for a batch run that holds. A conversation is
      // different: the frame arrives when the task is gone — reaped for
      // silence, most often — and the socket stays open afterwards, so
      // treating it as a log entry leaves the microphone streaming into a
      // task that will never answer, billing for it, while the user talks
      // to nothing. Ending here costs a tap and nothing else.
      case RealtimeErrorEvent():
        _appendProtocolEvent(event.wireType);
        _naturalCompletion ??= _completeNaturally(operationId);
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
    if (outcome.silencedChunk) {
      // The rest of an interrupted turn is discarded without ceremony; one
      // 'assistant_interrupted' entry already reported the event.
      return;
    }
    if (outcome.heldChunk) {
      // Retained behind a suspected interruption; it reaches the playback
      // model when the hold resolves, or never does.
      return;
    }
    if (outcome.flushedPreviousTurn) {
      voiceActivity.resetAi();
      _appendProtocolEvent('previous_turn_dropped');
    }
    if (outcome.droppedChunk) {
      _appendProtocolEvent('audio_chunk_dropped');
    } else {
      voiceActivity.addAiChunk(event.bytes);
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
    _micPipeline.stopWatchdog();
    _bargeIn.cancelHold();
    await _stopCapture();
    await player.complete();
    await player.stop();
    _playbackCoordinator.reset();
    voiceActivity.reset();
    noiseGate?.reset();
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
        isReconfiguring: false,
        microphoneActive: false,
      ),
    );
    // Wiro stops a task that has gone quiet, so that it stops charging for
    // one. Dialling straight back in would undo that on the user's behalf
    // and bill them for a conversation nobody is having, so the orb comes
    // back and waits for whoever wants to keep talking.
    if (_stopOperation == null) {
      _appendProtocolEvent('conversation_ended_remotely');
    }
  }

  void _handleEventError(Object error, int operationId) {
    if (_guard.isCurrent(operationId)) {
      unawaited(_fail(operationId, error));
    }
  }

  void _handleEventStreamDone(int operationId) {
    final terminalReceived = _terminalCompleter?.isCompleted ?? false;
    if (_guard.isCurrent(operationId) && !terminalReceived) {
      _appendProtocolEvent('socket_closed_remotely');
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
    final shouldRetry = _shouldRetry(error);
    // A conversation that was already streaming lost its socket, not its
    // task: the server was mid-conversation and never heard a hang-up, so
    // the task is worth dialling back into. Anything that broke earlier —
    // or a task the server itself cancelled — has nothing to return to.
    final canReuseTask =
        shouldRetry &&
        _taskLauncher.runResult != null &&
        error is! WiroCancellationFailure &&
        !(_terminalCompleter?.isCompleted ?? false) &&
        _snapshot.sessionState == RealtimeSessionState.streaming;
    final failureId = _guard.begin();
    _micPipeline.stopWatchdog();
    _bargeIn.cancelHold();
    if (!canReuseTask) {
      _taskLauncher.terminateBestEffort();
    }
    _taskLauncher.cancelPendingRequest();
    _elapsedClock.stop();
    await _stopCapture();
    await player.stop();
    _playbackCoordinator.reset();
    voiceActivity.reset();
    noiseGate?.reset();
    await audioSession.deactivate();
    await _dropSocket();
    if (!_guard.isCurrent(failureId)) {
      return;
    }
    if (shouldRetry) {
      _retryAttempt++;
      _publish(
        _snapshot.copyWith(
          status: ViewStatus.loading,
          sessionState: RealtimeSessionState.creatingTask,
          isReconfiguring: false,
          microphoneActive: false,
          errorMessage: null,
          protocolEvents: _protocolLog.add(
            'retry_scheduled:$_retryAttempt/$maxRetryAttempts',
          ),
        ),
      );
      await Future<void>.delayed(_retryDelay);
      if (!_guard.isCurrent(failureId)) {
        return;
      }
      _appendProtocolEvent('retry_started:$_retryAttempt');
      if (canReuseTask) {
        await _relaunch('reconnect', reuseTask: true, prepareAudio: true);
      } else {
        await _start(isRetry: true);
      }
      return;
    }
    _releaseLease();
    _publish(
      _snapshot.copyWith(
        status: ViewStatus.error,
        sessionState: RealtimeSessionState.failure,
        isReconfiguring: false,
        microphoneActive: false,
        errorMessage: _failureMapper.messageFor(error),
        canOpenSystemSettings: false,
        protocolEvents: _protocolLog.add(
          'failure:${_failureMapper.codeFor(error)}',
        ),
      ),
    );
    if (_isRecoverable(error)) {
      _scheduleAutoRestart();
    }
  }

  /// Restarting the app always brings the conversation back, so the page
  /// does the same thing by itself: rest a moment, then run a completely
  /// fresh start. Covers both a terminal failure and the server ending
  /// the task remotely. Unrecoverable errors — a denied microphone
  /// permission, another feature holding the hardware — stay on screen,
  /// because no number of restarts fixes those without the user acting.
  /// So does a backend that keeps refusing: [maxAutoRestarts] bounds the
  /// attempts, and the orb is worth more than another silent one.
  void _scheduleAutoRestart() {
    if (_guard.isDisposed || _autoRestartCycle >= maxAutoRestarts) {
      return;
    }
    _autoRestartTimer?.cancel();
    final shift = _autoRestartCycle > 2 ? 2 : _autoRestartCycle;
    _autoRestartCycle++;
    _appendProtocolEvent('auto_restart_scheduled');
    // The restart only fires while the screen still shows the state it
    // was armed from; anything else means the user or a newer operation
    // took over in the meantime.
    final armedState = _snapshot.sessionState;
    _autoRestartTimer = Timer(autoRestartDelay * (1 << shift), () {
      _autoRestartTimer = null;
      if (_guard.isDisposed || _snapshot.sessionState != armedState) {
        return;
      }
      unawaited(start());
    });
  }

  void _cancelAutoRestart() {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;
  }

  bool _shouldRetry(Object error) {
    if (_snapshot.isReconfiguring || _retryAttempt >= maxRetryAttempts) {
      return false;
    }
    return _isRecoverable(error);
  }

  bool _isRecoverable(Object error) {
    return switch (error) {
      WiroServerFailure() ||
      WiroNetworkFailure() ||
      WiroTimeoutFailure() ||
      WiroSocketFailure() ||
      WiroSocketConnectTimeoutFailure() ||
      WiroReadyTimeoutFailure() ||
      AudioFailure() => true,
      _ => false,
    };
  }

  Duration get _retryDelay {
    final multiplier = 1 << (_retryAttempt - 1);
    return retryBaseDelay * multiplier;
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

  void _startMicWatchdog(int operationId) {
    _watchdogOperationId = operationId;
    _micPipeline.startWatchdog();
  }

  void _handleMicStall() {
    final operationId = _watchdogOperationId;
    if (!_guard.isCurrent(operationId) ||
        _snapshot.sessionState != RealtimeSessionState.streaming) {
      return;
    }
    if (_snapshot.muted) {
      _micPipeline.markAlive();
      return;
    }
    _micPipeline.stopWatchdog();
    _appendProtocolEvent('microphone_stalled');
    unawaited(_fail(operationId, const AudioCaptureFailure()));
  }

  /// Counts on top of whatever the snapshot already holds, so a reconnect
  /// or a voice change continues the session clock instead of zeroing it.
  void _startElapsedTimer(int operationId) {
    final base = _snapshot.elapsed;
    _elapsedClock.start((elapsed) {
      if (!_guard.isCurrent(operationId)) {
        return;
      }
      final total = base + elapsed;
      _publish(_snapshot.copyWith(elapsed: total));
      _enforceSessionLimit(total);
    });
  }

  /// A conversation nobody is having still bills, so a session left open —
  /// a phone in a pocket, a forgotten tab — hangs up on itself. Ending it
  /// the way the user would means no reconnect follows.
  void _enforceSessionLimit(Duration elapsed) {
    final limit = maxSessionDuration;
    if (limit <= Duration.zero || elapsed < limit || _stopOperation != null) {
      return;
    }
    _appendProtocolEvent('session_limit_reached');
    unawaited(stop());
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
