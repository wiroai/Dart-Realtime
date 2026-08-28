import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

import 'support/transcription_test_dependencies.dart';

void main() {
  test('runs Voxtral and streams prefixed PCM after readiness', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();
    dependencies.recorder.emit(Uint8List.fromList([1, 2, 3]));
    await pumpEventQueue();

    expect(
      dependencies.audioSession.preparedProfiles,
      [RealtimeAudioProfile.transcription],
    );
    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.apiClient.lastParameters, {
      'transcriptionDelay': 'balanced',
    });
    expect(dependencies.session.sentAudio, [
      [1, 2, 3],
    ]);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.microphoneActive, isTrue);
  });

  test('a growing utterance refines the transcript in place', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello world'));

    expect(service.snapshot.transcript, 'Hello world');
    expect(
      service.snapshot.protocolEvents.where(
        (event) => event == 'task_output',
      ),
      hasLength(2),
    );
  });

  test('a new utterance joins the transcript instead of erasing it', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello world.'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:How are'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:How are you?'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Good.'));

    expect(
      service.snapshot.transcript,
      'Hello world. How are you? Good.',
    );
  });

  test('a shorter re-emit of the live utterance changes nothing', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello world'))
      ..emit(const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'));

    expect(service.snapshot.transcript, 'Hello world');
  });

  test('a new take starts from a blank transcript', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();
    dependencies.session.emit(
      const RealtimeOutputEvent('TRANSCRIPT_USER:Old take'),
    );
    await service.stop();

    await service.start();
    dependencies.session.emit(
      const RealtimeOutputEvent('TRANSCRIPT_USER:New take'),
    );

    expect(service.snapshot.transcript, 'New take');
  });

  test('stop releases microphone and sends one session end', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    final firstStop = service.stop();
    final secondStop = service.stop();
    await Future.wait([firstStop, secondStop]);

    expect(dependencies.recorder.stopCalls, 1);
    expect(dependencies.audioSession.deactivateCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.microphoneActive, isFalse);
  });

  test('a slow shutdown confirmation completes without an error', () async {
    final dependencies = TranscriptionTestDependencies(
      completeSessionEnd: false,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    await service.stop();

    expect(service.snapshot.status, ViewStatus.success);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.errorMessage, isNull);
    expect(service.snapshot.protocolEvents, contains('shutdown_timeout'));
  });

  test('maps denied microphone permission without running a task', () async {
    final dependencies = TranscriptionTestDependencies(
      preparationResult: AudioPreparationResult.permissionDenied,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);

    await service.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(service.snapshot.errorMessage, isNotEmpty);
  });

  test('cancels a pending Run request during stop', () async {
    final runCompleter = Completer<WiroRunResult>();
    final dependencies = TranscriptionTestDependencies(
      runCompleter: runCompleter,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    final starting = service.start();
    await pumpEventQueue();

    await service.stop();
    await starting;

    expect(dependencies.apiClient.lastCancellation?.isCancelled, isTrue);
    expect(dependencies.session.connectCalls, 0);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
  });

  test('terminates a Run result that arrives after stop', () async {
    final runCompleter = Completer<WiroRunResult>();
    final dependencies = TranscriptionTestDependencies(
      runCompleter: runCompleter,
      ignoreRunCancellation: true,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    final starting = service.start();
    await pumpEventQueue();

    final stopping = service.stop();
    runCompleter.complete(
      const WiroRunResult(
        taskId: 'orphan-task',
        taskToken: 'orphan-token',
      ),
    );
    await Future.wait([starting, stopping]);
    await pumpEventQueue();

    expect(dependencies.apiClient.terminatedTaskIds, ['orphan-task']);
    expect(dependencies.session.connectCalls, 0);
  });

  test('stream end stops capture before natural completion', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(
      const RealtimeStatusEvent(RealtimeEventType.streamEnded),
    );
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.stopping);
    expect(service.snapshot.microphoneActive, isFalse);
    expect(dependencies.recorder.stopCalls, 1);
    expect(dependencies.session.closeCalls, 0);
  });

  test('completes naturally after postprocess end', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.streamEnded),
      )
      ..emit(
        const RealtimeStatusEvent(
          RealtimeEventType.postprocessEnded,
        ),
      );
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.microphoneActive, isFalse);
    expect(dependencies.recorder.stopCalls, 1);
  });

  test('rejects unexpected server audio for STT', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([1, 2])),
    );
    await pumpEventQueue();

    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(service.snapshot.errorMessage, isNot(contains('1, 2')));
    expect(
      service.snapshot.protocolEvents,
      contains('failure:realtimeProtocol'),
    );
  });

  test('clear transcript is inactive-only business behavior', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();
    dependencies.session.emit(
      const RealtimeOutputEvent('TRANSCRIPT_USER:Keep me'),
    );

    service.clearTranscript();
    expect(service.snapshot.transcript, 'Keep me');

    await service.stop();
    service.clearTranscript();
    expect(service.snapshot.transcript, isEmpty);
  });

  test('stops an active session when audio is interrupted', () async {
    final dependencies = TranscriptionTestDependencies();
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

  test('commands after dispose are safe no-ops', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    await service.start();
    await service.dispose();
    final snapshot = service.snapshot;

    await service.start();
    await service.stop();
    service.clearTranscript();

    expect(dependencies.apiClient.runCalls, 1);
    expect(dependencies.recorder.startCalls, 1);
    expect(service.snapshot, snapshot);
  });

  test('a start after dispose does not strand the shared lease', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    await service.dispose();

    await service.start();

    expect(
      dependencies.sessionGuard.acquire(RealtimeSessionOwner.conversation),
      isNotNull,
    );
  });

  test('a start during another feature teardown waits it out', () async {
    final dependencies = TranscriptionTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    // The conversation tab was just left: its session is winding down and
    // still holds the lease for a beat.
    final departing = dependencies.sessionGuard.acquire(
      RealtimeSessionOwner.conversation,
    );

    final starting = service.start();
    await pumpEventQueue();
    expect(service.snapshot.status, ViewStatus.loading);
    dependencies.sessionGuard.release(departing);
    await starting;

    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
    expect(service.snapshot.errorMessage, isNull);
  });

  test('keeps the local protocol history bounded', () async {
    final dependencies = TranscriptionTestDependencies();
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
