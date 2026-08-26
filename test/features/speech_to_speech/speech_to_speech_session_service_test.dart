import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/config/conversation_config.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

import 'support/conversation_test_dependencies.dart';

void main() {
  test('starts GPT Realtime with verified PCM parameters', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();

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
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.microphoneActive, isTrue);
  });

  test('sends the configured persona and voice', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();

    // Editing ConversationConfig is the whole of turning the example into a
    // product, so what it holds has to reach the Run request untouched.
    expect(
      dependencies.apiClient.lastParameters,
      containsPair('system_instructions', ConversationConfig.persona),
    );
    expect(
      dependencies.apiClient.lastParameters,
      containsPair('voice', ConversationConfig.voice),
    );
  });

  test('a conversation left open ends itself at the configured ceiling',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      maxSessionDuration: const Duration(seconds: 1),
    );
    addTearDown(service.dispose);
    await service.start();

    await Future<void>.delayed(const Duration(milliseconds: 1400));

    expect(
      service.snapshot.protocolEvents,
      contains('session_limit_reached'),
    );
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    // Hanging up is not a failure, so nothing dials back in.
    expect(dependencies.apiClient.runCalls, 1);
  });

  test('a zero ceiling lets the conversation run on', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      maxSessionDuration: Duration.zero,
    );
    addTearDown(service.dispose);
    await service.start();

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
  });

  test('streams microphone and assistant PCM concurrently', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

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
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([3, 4])),
    );
    dependencies.recorder.emit(Uint8List.fromList([5]));

    expect(dependencies.session.sentAudio, [
      [5],
    ]);
    expect(service.snapshot.microphoneActive, isTrue);
  });

  test('a user transcript alone never cuts assistant audio', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

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
    expect(service.snapshot.userTranscript, 'Stop');
  });

  test('a new assistant turn drops the interrupted turn tail', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

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
      service.snapshot.protocolEvents,
      contains('previous_turn_dropped'),
    );
  });

  test('interruptAssistant cuts the turn and keeps the next one intact',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    // One second of audio keeps the assistant playhead in the future for
    // the whole test.
    dependencies.session.emit(RealtimeBinaryEvent(Uint8List(48000)));
    await pumpEventQueue();

    service.interruptAssistant();

    expect(dependencies.player.flushCalls, 1);
    expect(
      service.snapshot.protocolEvents,
      contains('assistant_silenced_by_user'),
    );

    // The rest of the silenced turn is discarded before the player; the
    // fake's flush already emptied what was fed earlier.
    dependencies.session.emit(RealtimeBinaryEvent(Uint8List.fromList([9])));
    await pumpEventQueue();
    expect(dependencies.player.fedChunks, isEmpty);

    // The turn that follows plays normally.
    dependencies.session
      ..emit(const RealtimeStatusEvent(RealtimeEventType.streamEnded))
      ..emit(RealtimeBinaryEvent(Uint8List.fromList([7])));
    await pumpEventQueue();
    expect(dependencies.player.fedChunks, [
      [7],
    ]);
  });

  test('interruptAssistant with nothing playing never latches', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    service.interruptAssistant();

    expect(dependencies.player.flushCalls, 0);

    dependencies.session.emit(RealtimeBinaryEvent(Uint8List.fromList([1])));
    await pumpEventQueue();
    expect(dependencies.player.fedChunks, [
      [1],
    ]);
  });

  test('a keyboard burst pauses the answer and hands it back', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    // One second of audio keeps the assistant playhead in the future for
    // the whole test.
    dependencies.session.emit(RealtimeBinaryEvent(Uint8List(48000)));
    await pumpEventQueue();

    // Three loud chunks are a suspicion: playback is silenced, but the
    // audio is only held, not discarded.
    for (var index = 0; index < 3; index++) {
      dependencies.recorder.emit(_micPcm(amplitude: 20000));
    }

    expect(dependencies.player.flushCalls, 1);
    expect(
      service.snapshot.protocolEvents,
      contains('assistant_playback_held'),
    );
    expect(
      service.snapshot.protocolEvents,
      isNot(contains('assistant_interrupted')),
    );

    // The burst dies the way a keystroke does, so the held remainder goes
    // back to the speaker.
    for (var index = 0; index < 3; index++) {
      dependencies.recorder.emit(_micPcm(amplitude: 0));
    }

    expect(
      service.snapshot.protocolEvents,
      contains('assistant_playback_resumed'),
    );
    expect(dependencies.player.fedChunks, hasLength(1));
  });

  test('sustained speech over the assistant commits the cut', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(RealtimeBinaryEvent(Uint8List(48000)));
    await pumpEventQueue();

    // Loud input that sustains the way only speech does: the hold at three
    // chunks becomes a committed interruption at eight.
    for (var index = 0; index < 8; index++) {
      dependencies.recorder.emit(_micPcm(amplitude: 20000));
    }

    expect(
      service.snapshot.protocolEvents,
      contains('assistant_interrupted'),
    );

    // The rest of the cut turn never reaches the player.
    dependencies.session.emit(RealtimeBinaryEvent(Uint8List.fromList([9])));
    await pumpEventQueue();
    expect(dependencies.player.fedChunks, isEmpty);
  });

  test('assigns progressive transcripts to the correct role', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

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

    expect(service.snapshot.userTranscript, 'Hello world');
    expect(service.snapshot.aiTranscript, 'Hi there');
  });

  test('mute drops microphone audio without closing the session', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    service.setMuted(muted: true);
    dependencies.recorder.emit(Uint8List.fromList([1]));
    service.setMuted(muted: false);
    dependencies.recorder.emit(Uint8List.fromList([2]));
    await pumpEventQueue();

    expect(dependencies.session.sentAudio, [
      [2],
    ]);
    expect(dependencies.session.closeCalls, 0);
    expect(service.snapshot.microphoneActive, isTrue);
  });

  test('stop releases all media and sends one session end', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    final firstStop = service.stop();
    final secondStop = service.stop();
    await Future.wait([firstStop, secondStop]);

    expect(dependencies.recorder.stopCalls, 1);
    expect(dependencies.player.stopCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.microphoneActive, isFalse);
  });

  test('AI turn end resumes listening without closing the session', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();
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
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.microphoneActive, isTrue);
  });

  test('postprocess end drains media and completes the session', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(
      const RealtimeStatusEvent(
        RealtimeEventType.postprocessEnded,
      ),
    );
    await pumpEventQueue();

    expect(dependencies.player.completeCalls, 1);
    expect(dependencies.recorder.stopCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
  });

  // Wiro stops a task that has gone quiet so it stops charging for it.
  // Opening a replacement would spend that saving on a conversation nobody
  // is having.
  test('a remote task end costs nothing more', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      autoRestartDelay: const Duration(milliseconds: 50),
    );
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(
      const RealtimeStatusEvent(RealtimeEventType.postprocessEnded),
    );
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(
      service.snapshot.protocolEvents,
      contains('conversation_ended_remotely'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(dependencies.apiClient.runCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(
      service.snapshot.protocolEvents,
      contains('conversation_ended_remotely'),
    );
  });

  test('a user stop never restarts by itself', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      autoRestartDelay: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    await service.start();

    await service.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(dependencies.apiClient.runCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(
      service.snapshot.protocolEvents,
      isNot(contains('conversation_ended_remotely')),
    );
  });

  test('permission denial does not create a task', () async {
    final dependencies = ConversationTestDependencies(
      preparationResult: AudioPreparationResult.permissionDenied,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(service.snapshot.errorMessage, isNotNull);
    // Asking again still works here, so no settings trip is offered.
    expect(service.snapshot.canOpenSystemSettings, isFalse);
  });

  test('a permanently denied microphone offers the settings trip', () async {
    final dependencies = ConversationTestDependencies(
      preparationResult: AudioPreparationResult.permissionPermanentlyDenied,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();

    expect(service.snapshot.canOpenSystemSettings, isTrue);

    await service.openSystemSettings();

    expect(dependencies.audioSession.openSystemSettingsCalls, 1);
  });

  test('a transport failure is not a settings problem', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emitError(const WiroSocketFailure());
    await pumpEventQueue();

    expect(service.snapshot.errorMessage, isNotNull);
    expect(service.snapshot.canOpenSystemSettings, isFalse);
  });

  test('retries a transient start failure before publishing failure', () async {
    final dependencies = ConversationTestDependencies(
      runErrors: const [WiroNetworkFailure()],
    );
    final service = dependencies.createService(maxRetryAttempts: 2);
    addTearDown(service.dispose);
    final publishedStates = <RealtimeSessionState>[];
    final subscription = service.snapshots.listen(
      (snapshot) => publishedStates.add(snapshot.sessionState),
    );
    addTearDown(subscription.cancel);

    await service.start();

    expect(dependencies.apiClient.runCalls, 2);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(publishedStates, isNot(contains(RealtimeSessionState.failure)));
    expect(service.snapshot.protocolEvents, contains('retry_started:1'));
  });

  test(
    'publishes failure only after transient retries are exhausted',
    () async {
      final dependencies = ConversationTestDependencies(
        runErrors: const [
          WiroNetworkFailure(),
          WiroNetworkFailure(),
          WiroNetworkFailure(),
        ],
      );
      final service = dependencies.createService(maxRetryAttempts: 2);
      addTearDown(service.dispose);

      await service.start();

      expect(dependencies.apiClient.runCalls, 3);
      expect(service.snapshot.status, ViewStatus.error);
      expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    },
  );

  test('stops an active session when audio is interrupted', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.audioSession.emitInterruption(
      RealtimeAudioInterruption.began,
    );
    await pumpEventQueue();

    expect(dependencies.session.sessionEndCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
  });

  // A dropped socket says nothing about the task behind it, and a new task
  // would be a new assistant with no memory of the conversation so far.
  test('a mid-stream socket failure returns to the same task', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(maxRetryAttempts: 1);
    addTearDown(service.dispose);
    await service.start();
    dependencies.session.emit(
      const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'),
    );

    dependencies.session.emitError(const WiroSocketFailure());
    await pumpEventQueue();

    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.apiClient.terminateCalls, 0);
    expect(dependencies.subscribedTaskTokens, ['task-token', 'task-token']);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.userTranscript, 'Hello');
    expect(
      service.snapshot.protocolEvents,
      contains('reconnect_accepted'),
    );
  });

  group('leaving the conversation', () {
    test('silences the microphone and frees the hardware', () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService(
        suspendGracePeriod: const Duration(seconds: 5),
      );
      addTearDown(service.dispose);
      await service.start();

      await service.suspend();

      expect(service.snapshot.isSuspended, isTrue);
      expect(service.snapshot.microphoneActive, isFalse);
      expect(dependencies.recorder.isRecording, isFalse);
      // Nothing was said to the server, so the task is still there to
      // come back to.
      expect(dependencies.session.sessionEndCalls, 0);
      expect(dependencies.apiClient.terminateCalls, 0);
      // Another feature may take the microphone while nobody is talking.
      expect(
        dependencies.sessionGuard.acquire(RealtimeSessionOwner.transcription),
        isNotNull,
      );
    });

    test('coming back continues the same task', () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService(
        suspendGracePeriod: const Duration(seconds: 5),
      );
      addTearDown(service.dispose);
      await service.start();
      dependencies.session.emit(
        const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'),
      );
      await service.suspend();

      await service.resume();

      expect(service.snapshot.isSuspended, isFalse);
      expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
      expect(service.snapshot.userTranscript, 'Hello');
      expect(dependencies.apiClient.runCalls, 1);
      expect(dependencies.subscribedTaskTokens, ['task-token', 'task-token']);
    });

    test('a speaker who never comes back is hung up on', () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService(
        suspendGracePeriod: const Duration(milliseconds: 40),
      );
      addTearDown(service.dispose);
      await service.start();
      await service.suspend();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.snapshot.sessionState, RealtimeSessionState.completed);
      expect(service.snapshot.isSuspended, isFalse);
      expect(service.snapshot.protocolEvents, contains('hold_expired'));
      // Nobody ended the session cleanly, so the task has to be told.
      expect(dependencies.apiClient.terminateCalls, 1);
    });

    test('a lapsed hold is not resumed even if the timer never ran',
        () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService(
        suspendGracePeriod: const Duration(milliseconds: 20),
      );
      addTearDown(service.dispose);
      await service.start();
      await service.suspend();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await service.resume();

      expect(service.snapshot.sessionState, RealtimeSessionState.completed);
      expect(dependencies.apiClient.runCalls, 1);
    });

    // The shipped default: a billed task is not held for someone who is
    // no longer looking at it.
    test('the configured default ends the conversation outright', () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService();
      addTearDown(service.dispose);
      await service.start();

      await service.suspend();

      expect(service.snapshot.isSuspended, isFalse);
      expect(service.snapshot.sessionState, RealtimeSessionState.completed);
      expect(dependencies.session.sessionEndCalls, 1);
    });

    test('an idle conversation has nothing to hold', () async {
      final dependencies = ConversationTestDependencies();
      final service = dependencies.createService();
      addTearDown(service.dispose);

      await service.suspend();
      await service.resume();

      expect(service.snapshot.sessionState, RealtimeSessionState.idle);
      expect(dependencies.apiClient.runCalls, 0);
    });
  });

  test('a task that refuses the reconnect is replaced', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(maxRetryAttempts: 1);
    addTearDown(service.dispose);
    await service.start();
    dependencies.session.connectError = const WiroSocketFailure();

    dependencies.session.emitError(const WiroSocketFailure());
    await pumpEventQueue();

    expect(service.snapshot.protocolEvents, contains('reconnect_refused'));
    expect(dependencies.apiClient.terminateCalls, 1);
    expect(dependencies.apiClient.runCalls, 2);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
  });

  test('a dead microphone reconnects, then fails once retries run out',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      maxRetryAttempts: 1,
      micStallTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(service.dispose);

    // The fake recorder never emits a chunk, which is exactly what a
    // stale native engine looks like after a hot restart.
    await service.start();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(service.snapshot.protocolEvents, contains('microphone_stalled'));
    // A broken microphone is the phone's problem, not the task's, so the
    // conversation rejoins the one it already has.
    expect(dependencies.apiClient.runCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
  });

  test('a recoverable failure restarts the conversation by itself',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      autoRestartDelay: const Duration(milliseconds: 50),
    );
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emitError(const WiroSocketFailure());
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(
      service.snapshot.protocolEvents,
      contains('auto_restart_scheduled'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(dependencies.apiClient.runCalls, 2);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
  });

  // An orb that keeps reconnecting on its own and keeps failing looks
  // exactly like an orb that is listening, so the retrying stops and the
  // tap comes back.
  test('a backend that keeps refusing hands the orb back', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService(
      autoRestartDelay: const Duration(milliseconds: 20),
      maxAutoRestarts: 1,
    );
    addTearDown(service.dispose);
    await service.start();

    for (var attempt = 0; attempt < 4; attempt++) {
      dependencies.session.emitError(const WiroSocketFailure());
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    // The first start plus the one restart it was allowed, and nothing
    // launched afterwards.
    expect(dependencies.apiClient.runCalls, 2);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
  });

  test('a denied permission never restarts by itself', () async {
    final dependencies = ConversationTestDependencies(
      preparationResult: AudioPreparationResult.permissionDenied,
    );
    final service = dependencies.createService(
      autoRestartDelay: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);

    await service.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(dependencies.apiClient.runCalls, 0);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(
      service.snapshot.protocolEvents,
      isNot(contains('auto_restart_scheduled')),
    );
  });

  test('a failure reports what happened in one line', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emitError(const WiroSocketFailure());
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(service.snapshot.errorMessage, isNotNull);
  });

  // The socket outlives the task it was carrying, so a session left up
  // after task_error streams the microphone into nothing — and bills for
  // it — while the user wonders why they are not being heard.
  test('a task_error hands the conversation back to the orb', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(const RealtimeErrorEvent('task_error'));
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.microphoneActive, isFalse);
    expect(dependencies.recorder.isRecording, isFalse);
    // Ending is not retrying: no replacement task is bought for the user.
    expect(dependencies.apiClient.runCalls, 1);
    expect(service.snapshot.protocolEvents, contains('task_error'));
  });

  test('a command after dispose is ignored, not an error', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    await service.start();
    await service.dispose();

    await service.start();
    await service.stop();
    service.setMuted(muted: true);

    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.recorder.startCalls, 1);
  });

  test('a start after dispose does not strand the shared lease', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    await service.dispose();

    await service.start();

    // The guard is global, so a lease stranded here would lock speech to text
    // and text to speech out of the microphone for the rest of the process.
    expect(
      dependencies.sessionGuard.acquire(RealtimeSessionOwner.transcription),
      isNotNull,
    );
  });

  test('an edited parameter rebuilds the live task with the new value',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();
    dependencies.session.emit(
      const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'),
    );

    service.parameters.require('turn_detection_threshold').value = '0.4';
    await service.applyParameterChanges();

    expect(dependencies.apiClient.runCalls, 2);
    expect(
      dependencies.apiClient.lastParameters,
      containsPair('turn_detection_threshold', 0.4),
    );
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.userTranscript, 'Hello');
    expect(
      service.snapshot.protocolEvents,
      contains('settings_change_completed'),
    );
  });

  test('an untouched settings form leaves the session alone', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    await service.applyParameterChanges();

    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.session.closeCalls, 0);
    expect(service.snapshot.isReconfiguring, isFalse);
  });

  test('parameters edited before the session starts need no rebuild',
      () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);

    service.parameters.require('turn_detection_silence_ms').value = '400';
    await service.applyParameterChanges();
    await service.start();

    expect(dependencies.apiClient.runCalls, 1);
    expect(
      dependencies.apiClient.lastParameters,
      containsPair('turn_detection_silence_ms', 400),
    );
  });

  test('keeps the local protocol history bounded', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    for (var index = 0; index < 50; index++) {
      dependencies.session.emit(
        RealtimeUnknownEvent('future_event_$index'),
      );
    }

    expect(service.snapshot.protocolEvents, hasLength(40));
  });
}

/// One 20 ms microphone chunk of constant amplitude at the 24 kHz 16-bit
/// mono wire format, loud enough at 20000 to clear the barge-in bar.
Uint8List _micPcm({required int amplitude}) {
  const sampleCount = 480;
  final data = ByteData(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}
