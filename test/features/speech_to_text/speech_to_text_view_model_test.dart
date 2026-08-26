import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';

void main() {
  ({
    FakeTranscriptionSessionController controller,
    SpeechToTextViewModel viewModel,
  })
  build() {
    final controller = FakeTranscriptionSessionController();
    final viewModel = SpeechToTextViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);
    return (controller: controller, viewModel: viewModel);
  }

  test('takes the fixed model from the session', () {
    final harness = build();

    expect(harness.viewModel.model, harness.controller.model);
  });

  test('adopts a session that is already transcribing', () {
    final controller = FakeTranscriptionSessionController()
      ..snapshot = const TranscriptionSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        transcript: 'in progress',
      );

    final viewModel = SpeechToTextViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);

    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.transcript, 'in progress');
  });

  test('projects every drawn snapshot field onto view state', () {
    final harness = build();

    harness.controller.publish(
      const TranscriptionSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        elapsed: Duration(seconds: 7),
        transcript: 'hello',
        microphoneActive: true,
        errorMessage: 'boom',
        protocolEvents: ['first', 'second'],
      ),
    );

    final state = harness.viewModel.state;
    expect(state.sessionState, RealtimeSessionState.streaming);
    expect(state.elapsed, const Duration(seconds: 7));
    expect(state.transcript, 'hello');
    expect(state.microphoneActive, isTrue);
    expect(state.errorMessage, 'boom');
    expect(state.protocolEvents, ['first', 'second']);
  });

  test('clearing an error message propagates the null', () {
    final harness = build();
    harness.controller.publish(
      const TranscriptionSessionSnapshot(errorMessage: 'boom'),
    );

    harness.controller.publish(const TranscriptionSessionSnapshot());

    expect(harness.viewModel.state.errorMessage, isNull);
  });

  test('a reveal request opens the protocol panel', () {
    final harness = build();

    harness.controller.publish(
      const TranscriptionSessionSnapshot(revealProtocolPanel: true),
    );

    expect(harness.viewModel.state.protocolExpanded, isTrue);
  });

  test('a collapsed panel stays closed while reveal holds', () {
    final harness = build();
    harness.controller.publish(
      const TranscriptionSessionSnapshot(revealProtocolPanel: true),
    );

    harness.viewModel.toggleProtocolPanel();
    harness.controller.publish(
      const TranscriptionSessionSnapshot(
        revealProtocolPanel: true,
        transcript: 'new state',
      ),
    );

    expect(harness.viewModel.state.protocolExpanded, isFalse);
  });

  test('a later failure reopens a panel the user closed', () {
    final harness = build();
    harness.controller.publish(
      const TranscriptionSessionSnapshot(revealProtocolPanel: true),
    );
    harness.viewModel.toggleProtocolPanel();

    harness.controller.publish(const TranscriptionSessionSnapshot());
    harness.controller.publish(
      const TranscriptionSessionSnapshot(revealProtocolPanel: true),
    );

    expect(harness.viewModel.state.protocolExpanded, isTrue);
  });

  test('commands are delegated to the session', () async {
    final harness = build();

    await harness.viewModel.start();
    await harness.viewModel.stop();
    harness.viewModel.clearTranscript();

    expect(harness.controller.startCalls, 1);
    expect(harness.controller.stopCalls, 1);
    expect(harness.controller.clearCalls, 1);
  });

  test('toggling the panel does not call the session', () {
    final harness = build();

    harness.viewModel.toggleProtocolPanel();

    expect(harness.viewModel.state.protocolExpanded, isTrue);
    expect(harness.controller.commandCalls, 0);
  });

  test('dispose releases the session and stops listening', () {
    final controller = FakeTranscriptionSessionController();

    SpeechToTextViewModel(sessionService: controller).dispose();
    controller.publish(
      const TranscriptionSessionSnapshot(transcript: 'late'),
    );

    expect(controller.disposeCalls, 1);
    expect(controller.hasListeners, isFalse);
  });
}

final class FakeTranscriptionSessionController
    implements TranscriptionSessionController {
  final StreamController<TranscriptionSessionSnapshot> _snapshots =
      StreamController<TranscriptionSessionSnapshot>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;
  int clearCalls = 0;
  int disposeCalls = 0;

  int get commandCalls => startCalls + stopCalls + clearCalls;

  bool get hasListeners => _snapshots.hasListener;

  @override
  TranscriptionSessionSnapshot snapshot = const TranscriptionSessionSnapshot();

  @override
  Stream<TranscriptionSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  ModelDefinition get model => WiroModelCatalog.voxtralMiniRealtime;

  @override
  late final ModelParameterValues parameters = ModelParameterValues(
    model.firstPassFields,
  );

  @override
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  void clearTranscript() {
    clearCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void publish(TranscriptionSessionSnapshot next) {
    snapshot = next;
    _snapshots.add(next);
  }
}
