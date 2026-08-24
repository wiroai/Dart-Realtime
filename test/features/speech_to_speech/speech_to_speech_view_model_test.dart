import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

void main() {
  ({
    FakeConversationSessionController controller,
    SpeechToSpeechViewModel viewModel,
  })
  build() {
    final controller = FakeConversationSessionController();
    final viewModel = SpeechToSpeechViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);
    return (controller: controller, viewModel: viewModel);
  }

  test('takes the selected model from the session', () {
    final harness = build();

    expect(harness.viewModel.state.selectedModel, harness.controller.model);
  });

  test('adopts a session that is already mid-conversation', () {
    final controller = FakeConversationSessionController()
      ..snapshot = const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        userTranscript: 'in progress',
      );

    final viewModel = SpeechToSpeechViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);

    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.userTranscript, 'in progress');
  });

  test('projects every snapshot field onto view state', () {
    final harness = build();

    harness.controller.publish(
      const ConversationSessionSnapshot(
        status: ViewStatus.success,
        sessionState: RealtimeSessionState.streaming,
        elapsed: Duration(seconds: 7),
        userTranscript: 'hello',
        aiTranscript: 'hi there',
        microphoneActive: true,
        muted: true,
        speakerEnabled: false,
        errorMessage: 'boom',
        protocolEvents: ['first', 'second'],
      ),
    );

    final state = harness.viewModel.state;
    expect(state.status, ViewStatus.success);
    expect(state.sessionState, RealtimeSessionState.streaming);
    expect(state.elapsed, const Duration(seconds: 7));
    expect(state.userTranscript, 'hello');
    expect(state.aiTranscript, 'hi there');
    expect(state.microphoneActive, isTrue);
    expect(state.muted, isTrue);
    expect(state.speakerEnabled, isFalse);
    expect(state.errorMessage, 'boom');
    expect(state.protocolEvents, ['first', 'second']);
  });

  test('clearing an error message propagates the null', () {
    final harness = build();
    harness.controller.publish(
      const ConversationSessionSnapshot(errorMessage: 'boom'),
    );

    harness.controller.publish(const ConversationSessionSnapshot());

    expect(harness.viewModel.state.errorMessage, isNull);
  });

  test('a reveal request opens the protocol panel', () {
    final harness = build();
    expect(harness.viewModel.state.protocolExpanded, isFalse);

    harness.controller.publish(
      const ConversationSessionSnapshot(revealProtocolPanel: true),
    );

    expect(harness.viewModel.state.protocolExpanded, isTrue);
  });

  test('a collapsed panel stays closed while the reveal request holds', () {
    final harness = build();
    harness.controller.publish(
      const ConversationSessionSnapshot(revealProtocolPanel: true),
    );

    harness.viewModel.toggleProtocolPanel();
    harness.controller.publish(
      const ConversationSessionSnapshot(
        revealProtocolPanel: true,
        muted: true,
      ),
    );

    expect(harness.viewModel.state.protocolExpanded, isFalse);
  });

  test('a later failure reopens a panel the user had closed', () {
    final harness = build();
    harness.controller.publish(
      const ConversationSessionSnapshot(revealProtocolPanel: true),
    );
    harness.viewModel.toggleProtocolPanel();

    harness.controller.publish(const ConversationSessionSnapshot());
    harness.controller.publish(
      const ConversationSessionSnapshot(revealProtocolPanel: true),
    );

    expect(harness.viewModel.state.protocolExpanded, isTrue);
  });

  test('toggling the panel does not disturb session state', () {
    final harness = build();
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
      ),
    );

    harness.viewModel.toggleProtocolPanel();

    expect(harness.viewModel.state.protocolExpanded, isTrue);
    expect(
      harness.viewModel.state.sessionState,
      RealtimeSessionState.streaming,
    );
  });

  test('commands are delegated to the session', () async {
    final harness = build();

    await harness.viewModel.start();
    await harness.viewModel.stop();
    harness.viewModel
      ..muteChanged(muted: true)
      ..speakerChanged(enabled: false);

    expect(harness.controller.startCalls, 1);
    expect(harness.controller.stopCalls, 1);
    expect(harness.controller.muteRequests, [true]);
    expect(harness.controller.speakerRequests, [false]);
  });

  test('dispose releases the session and stops listening', () {
    final controller = FakeConversationSessionController();

    SpeechToSpeechViewModel(sessionService: controller).dispose();

    // A snapshot arriving after dispose must not reach the notifier, which
    // would throw for emitting on a disposed ValueNotifier.
    controller.publish(
      const ConversationSessionSnapshot(userTranscript: 'late'),
    );

    expect(controller.disposeCalls, 1);
    expect(controller.hasListeners, isFalse);
  });
}

final class FakeConversationSessionController
    implements ConversationSessionController {
  final StreamController<ConversationSessionSnapshot> _snapshots =
      StreamController<ConversationSessionSnapshot>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<bool> muteRequests = [];
  final List<bool> speakerRequests = [];

  bool get hasListeners => _snapshots.hasListener;

  @override
  ConversationSessionSnapshot snapshot = const ConversationSessionSnapshot();

  @override
  Stream<ConversationSessionSnapshot> get snapshots => _snapshots.stream;

  @override
  ModelDefinition get model => WiroModelCatalog.gptRealtimeMini;

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
  Future<void> changeVoice(String voice) async {}

  @override
  void setMuted({required bool muted}) {
    muteRequests.add(muted);
  }

  @override
  void setSpeakerEnabled({required bool enabled}) {
    speakerRequests.add(enabled);
  }

  /// Unlike the real service this keeps the stream open, so a test can prove
  /// the view model stopped listening rather than the controller shutting down.
  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void publish(ConversationSessionSnapshot next) {
    snapshot = next;
    _snapshots.add(next);
  }
}
