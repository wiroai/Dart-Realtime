import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_controller.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_snapshot.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

void main() {
  test('applies the current snapshot in the constructor', () {
    final controller = FakeSpeechSessionController()
      ..snapshot = const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.voxcpm2,
        sessionState: RealtimeSessionState.streaming,
        isPlaying: true,
      );
    final viewModel = TextToSpeechViewModel(
      sessionService: controller,
    );
    addTearDown(viewModel.dispose);

    expect(viewModel.state.selectedModel, WiroModelCatalog.voxcpm2);
    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.isPlaying, isTrue);
  });

  test('projects every drawn snapshot field', () {
    final harness = _build();
    harness.controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.voxcpm2,
        sessionState: RealtimeSessionState.streaming,
        elapsed: Duration(seconds: 4),
        isPlaying: true,
        errorMessage: 'error',
        protocolEvents: ['event'],
      ),
    );

    final state = harness.viewModel.state;
    expect(state.selectedModel, WiroModelCatalog.voxcpm2);
    expect(state.sessionState, RealtimeSessionState.streaming);
    expect(state.isPlaying, isTrue);
    expect(state.errorMessage, 'error');
    expect(state.protocolEvents, ['event']);
  });

  test('delegates commands and service getters', () async {
    final harness = _build();

    harness.viewModel.selectModel(WiroModelCatalog.voxcpm2);
    await harness.viewModel.start();
    await harness.viewModel.stop();

    expect(harness.controller.selectCalls, 1);
    expect(harness.controller.startCalls, 1);
    expect(harness.controller.stopCalls, 1);
    expect(
      harness.viewModel.parameters,
      same(harness.controller.parameters),
    );
    expect(
      harness.viewModel.promptNotifier,
      same(harness.controller.promptNotifier),
    );
    expect(
      harness.viewModel.sessionGuard,
      same(harness.controller.sessionGuard),
    );
  });

  test('protocol reveal is edge-triggered', () {
    final harness = _build();
    harness.controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.mossTtsRealtime,
        revealProtocolPanel: true,
      ),
    );
    expect(harness.viewModel.state.protocolExpanded, isTrue);

    harness.viewModel.toggleProtocolPanel();
    harness.controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.mossTtsRealtime,
        revealProtocolPanel: true,
        protocolEvents: ['held'],
      ),
    );
    expect(harness.viewModel.state.protocolExpanded, isFalse);

    harness.controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.mossTtsRealtime,
      ),
    );
    harness.controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.mossTtsRealtime,
        revealProtocolPanel: true,
      ),
    );
    expect(harness.viewModel.state.protocolExpanded, isTrue);
  });

  test('panel toggle remains UI-only', () {
    final harness = _build();

    harness.viewModel.toggleProtocolPanel();

    expect(harness.viewModel.state.protocolExpanded, isTrue);
    expect(harness.controller.commandCalls, 0);
  });

  test('dispose releases service and snapshot subscription', () {
    final controller = FakeSpeechSessionController();

    TextToSpeechViewModel(sessionService: controller).dispose();
    controller.publish(
      const SpeechSessionSnapshot(
        selectedModel: WiroModelCatalog.mossTtsRealtime,
        isPlaying: true,
      ),
    );

    expect(controller.disposeCalls, 1);
    expect(controller.hasListeners, isFalse);
  });
}

({
  FakeSpeechSessionController controller,
  TextToSpeechViewModel viewModel,
})
_build() {
  final controller = FakeSpeechSessionController();
  final viewModel = TextToSpeechViewModel(sessionService: controller);
  addTearDown(viewModel.dispose);
  return (controller: controller, viewModel: viewModel);
}

final class FakeSpeechSessionController implements SpeechSessionController {
  final StreamController<SpeechSessionSnapshot> _snapshots =
      StreamController<SpeechSessionSnapshot>.broadcast(sync: true);

  int selectCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  int get commandCalls => selectCalls + startCalls + stopCalls;

  bool get hasListeners => _snapshots.hasListener;

  @override
  SpeechSessionSnapshot snapshot = const SpeechSessionSnapshot(
    selectedModel: WiroModelCatalog.mossTtsRealtime,
  );

  @override
  Stream<SpeechSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  late final ModelParameterValues parameters = ModelParameterValues(
    WiroModelCatalog.mossTtsRealtime.firstPassFields,
  );

  @override
  final RealtimeSessionGuard sessionGuard = RealtimeSessionGuard();

  @override
  ValueNotifier<String> get promptNotifier => parameters.require('text');

  @override
  void selectModel(ModelDefinition model) {
    selectCalls++;
  }

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void publish(SpeechSessionSnapshot next) {
    snapshot = next;
    _snapshots.add(next);
  }
}
