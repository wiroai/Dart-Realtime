import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

import 'support/speech_test_dependencies.dart';

void main() {
  test('requires non-empty trimmed text', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = '   ';

    await service.start();

    expect(dependencies.apiClient.runCalls, 0);
    expect(dependencies.audioSession.preparedProfiles, isEmpty);
    expect(service.snapshot.status, ViewStatus.error);
  });

  test('runs MOSS with text and prepares playback', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = '  Hello realtime speech.  ';

    await service.start();

    expect(
      dependencies.audioSession.preparedProfiles,
      [RealtimeAudioProfile.speech],
    );
    expect(dependencies.apiClient.lastParameters, {
      'text': 'Hello realtime speech.',
    });
    expect(dependencies.session.connectCalls, 1);
    expect(dependencies.player.startCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.streaming);
  });

  test('selects inactive TTS models and changes the prompt field', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    final oldPrompt = service.promptNotifier;

    service.selectModel(WiroModelCatalog.voxcpm2);
    service.promptNotifier.value = 'Vox prompt';
    await service.start();

    expect(
      () => oldPrompt.addListener(() {}),
      throwsFlutterError,
    );
    expect(service.snapshot.selectedModel, WiroModelCatalog.voxcpm2);
    expect(dependencies.apiClient.lastParameters, {
      'prompt': 'Vox prompt',
      'cfgValue': 2.0,
      'inferenceSteps': 10,
    });
  });

  test('reselecting the model resets its parameter values', () {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    final oldPrompt = service.promptNotifier..value = 'Discard me';

    service.selectModel(WiroModelCatalog.mossTtsRealtime);

    expect(service.promptNotifier.value, isEmpty);
    expect(
      () => oldPrompt.addListener(() {}),
      throwsFlutterError,
    );
  });

  test('rejects model changes while active or in another direction', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);

    service.selectModel(WiroModelCatalog.voxtralMiniRealtime);
    expect(
      service.snapshot.selectedModel.direction,
      RealtimeDirection.textToSpeech,
    );
    service.promptNotifier.value = 'Hello';
    await service.start();
    service.selectModel(WiroModelCatalog.voxcpm2);

    expect(
      service.snapshot.selectedModel.modelSlug,
      WiroModelCatalog.mossTtsRealtime.modelSlug,
    );
  });

  test('queues PCM in FIFO and drains before natural completion', () async {
    final drain = Completer<void>();
    final dependencies = SpeechTestDependencies(
      playbackCompleter: drain,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    dependencies.session
      ..emit(RealtimeBinaryEvent(Uint8List.fromList([1, 2])))
      ..emit(RealtimeBinaryEvent(Uint8List.fromList([3, 4])))
      ..emit(
        const RealtimeStatusEvent(RealtimeEventType.streamEnded),
      )
      ..emit(
        const RealtimeStatusEvent(
          RealtimeEventType.postprocessEnded,
        ),
      );
    await pumpEventQueue();

    expect(dependencies.player.fedChunks, [
      [1, 2],
      [3, 4],
    ]);
    expect(service.snapshot.isPlaying, isTrue);
    expect(service.snapshot.sessionState, RealtimeSessionState.stopping);

    drain.complete();
    await pumpEventQueue();
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
    expect(service.snapshot.isPlaying, isFalse);
    expect(dependencies.player.completeCalls, 1);
  });

  test('early stop flushes playback and ends once', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();
    dependencies.session.emit(
      RealtimeBinaryEvent(Uint8List.fromList([1, 2])),
    );

    await Future.wait([service.stop(), service.stop()]);

    expect(dependencies.player.stopCalls, 1);
    expect(dependencies.session.sessionEndCalls, 1);
    expect(dependencies.session.closeCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
  });

  test('maps playback failures to a sanitized failure', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    dependencies.player.emitFailure();
    await pumpEventQueue();

    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.errorMessage, isNot(contains('platform')));
  });

  test('rejects malformed realtime audio frames', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    dependencies.session.emit(const RealtimeMalformedEvent());
    await pumpEventQueue();

    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.sessionState, RealtimeSessionState.failure);
  });

  test('cancels pending Run and terminates a stale result', () async {
    final runCompleter = Completer<WiroRunResult>();
    final dependencies = SpeechTestDependencies(
      runCompleter: runCompleter,
      ignoreRunCancellation: true,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    final starting = service.start();
    await pumpEventQueue();

    final stopping = service.stop();
    expect(dependencies.apiClient.lastCancellation?.isCancelled, isTrue);
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

  test('reports terminal shutdown timeout', () async {
    final dependencies = SpeechTestDependencies(
      completeSessionEnd: false,
    );
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    await service.stop();

    expect(service.snapshot.status, ViewStatus.error);
    expect(service.snapshot.protocolEvents, contains('shutdown_timeout'));
  });

  test('stops an active session on interruption', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    dependencies.audioSession.emitInterruption(
      RealtimeAudioInterruption.began,
    );
    await pumpEventQueue();

    expect(dependencies.session.sessionEndCalls, 1);
    expect(service.snapshot.sessionState, RealtimeSessionState.completed);
  });

  test('keeps protocol history bounded', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
    await service.start();

    for (var index = 0; index < 50; index++) {
      dependencies.session.emit(
        RealtimeUnknownEvent('future_event_$index'),
      );
    }

    expect(service.snapshot.protocolEvents, hasLength(40));
  });

  test('commands after dispose are safe no-ops', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    await service.dispose();
    final snapshot = service.snapshot;

    service.selectModel(WiroModelCatalog.voxcpm2);
    await service.start();
    await service.stop();

    expect(dependencies.apiClient.runCalls, 0);
    expect(service.snapshot, snapshot);
  });

  test('start after dispose does not strand the shared lease', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    await service.dispose();

    await service.start();

    expect(
      dependencies.sessionGuard.acquire(
        RealtimeSessionOwner.conversation,
      ),
      isNotNull,
    );
  });

  test('stream and postprocess racing stop remain idempotent', () async {
    final dependencies = SpeechTestDependencies();
    final service = dependencies.createService();
    addTearDown(service.dispose);
    service.promptNotifier.value = 'Hello';
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
    await service.stop();
    await pumpEventQueue();

    expect(dependencies.session.closeCalls, 1);
    expect(dependencies.player.completeCalls, 1);
    expect(
      service.snapshot.sessionState,
      RealtimeSessionState.completed,
    );
  });
}
