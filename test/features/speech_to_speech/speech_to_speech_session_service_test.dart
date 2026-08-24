import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
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

  test('speaker disable preserves microphone streaming', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();

    service.setSpeakerEnabled(enabled: false);
    dependencies.recorder.emit(Uint8List.fromList([7]));
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([8])),
    );
    await pumpEventQueue();

    expect(dependencies.player.isEnabled, isFalse);
    expect(dependencies.session.sentAudio, [
      [7],
    ]);
    expect(dependencies.player.fedChunks, isEmpty);
    expect(dependencies.session.closeCalls, 0);
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
  });

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

  test('a failure asks the view to reveal diagnostics', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    await service.start();
    expect(service.snapshot.revealProtocolPanel, isFalse);

    dependencies.session.emit(const RealtimeErrorEvent('task_error'));
    await pumpEventQueue();

    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
    expect(service.snapshot.revealProtocolPanel, isTrue);
    expect(service.snapshot.errorMessage, isNotNull);
  });

  test('a command after dispose is ignored, not an error', () async {
    final dependencies = ConversationTestDependencies();
    final service = dependencies.createService();
    await service.start();
    await service.dispose();

    await service.start();
    await service.stop();
    service
      ..setMuted(muted: true)
      ..setSpeakerEnabled(enabled: false);

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
