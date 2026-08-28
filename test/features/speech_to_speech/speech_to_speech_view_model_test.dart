import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';
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

  test('adopts a session that is already mid-conversation', () {
    final controller = FakeConversationSessionController()
      ..snapshot = const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        muted: true,
      );

    final viewModel = SpeechToSpeechViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);

    expect(viewModel.state.sessionState, RealtimeSessionState.streaming);
    expect(viewModel.state.muted, isTrue);
  });

  test('projects onto view state only what the screen draws', () {
    final harness = build();

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        muted: true,
        isReconfiguring: true,
        errorMessage: 'boom',
        canOpenSystemSettings: true,
      ),
    );

    final state = harness.viewModel.state;
    expect(state.sessionState, RealtimeSessionState.streaming);
    expect(state.muted, isTrue);
    expect(state.isReconfiguring, isTrue);
    expect(state.errorMessage, 'boom');
    expect(state.canOpenSystemSettings, isTrue);
  });

  test('snapshot fields the screen never draws cause no rebuild', () {
    final harness = build();
    harness.controller.publish(const ConversationSessionSnapshot());
    var notifications = 0;
    harness.viewModel.addListener(() => notifications++);

    // Transcripts, the clock and the protocol log churn constantly during
    // a live conversation; none of them may reach the notifier.
    harness.controller.publish(
      const ConversationSessionSnapshot(
        elapsed: Duration(seconds: 7),
        userTranscript: 'hello',
        aiTranscript: 'hi there',
        protocolEvents: ['first', 'second'],
      ),
    );

    expect(notifications, isZero);
  });

  test('clearing an error message propagates the null', () {
    final harness = build();
    harness.controller.publish(
      const ConversationSessionSnapshot(errorMessage: 'boom'),
    );

    harness.controller.publish(const ConversationSessionSnapshot());

    expect(harness.viewModel.state.errorMessage, isNull);
  });

  test('start raises reportsConnecting and going live lowers it', () async {
    final harness = build();
    expect(harness.viewModel.state.reportsConnecting, isFalse);

    await harness.viewModel.start();
    expect(harness.viewModel.state.reportsConnecting, isTrue);

    // The connect steps keep the asked-for wait open…
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
      ),
    );
    expect(harness.viewModel.state.reportsConnecting, isTrue);

    // …and the first audible moment closes it for good.
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
      ),
    );
    expect(harness.viewModel.state.reportsConnecting, isFalse);
  });

  test('a failed start also lowers reportsConnecting', () async {
    final harness = build();
    await harness.viewModel.start();

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.failure,
        errorMessage: 'boom',
      ),
    );

    expect(harness.viewModel.state.reportsConnecting, isFalse);
  });

  test('a session connecting on its own raises no reportsConnecting', () {
    final harness = build();

    // A dropped socket being rebuilt, a voice change, an auto-restart:
    // nobody tapped, so nobody is waiting.
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.connectingSocket,
      ),
    );

    expect(harness.viewModel.state.reportsConnecting, isFalse);
  });

  test('commands are delegated to the session', () async {
    final harness = build();

    await harness.viewModel.start();
    await harness.viewModel.stop();
    harness.viewModel.muteChanged(muted: true);

    expect(harness.controller.startCalls, 1);
    expect(harness.controller.stopCalls, 1);
    expect(harness.controller.muteRequests, [true]);
  });

  test('dispose releases the session and stops listening', () {
    final controller = FakeConversationSessionController();

    SpeechToSpeechViewModel(sessionService: controller).dispose();

    // A snapshot arriving after dispose must not reach the notifier, which
    // would throw for emitting on a disposed ValueNotifier.
    controller.publish(
      const ConversationSessionSnapshot(muted: true),
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
  final ConversationVoiceActivity voiceActivity = ConversationVoiceActivity();

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
  Future<void> suspend() async {}

  @override
  Future<void> resume() async {}

  @override
  void setMuted({required bool muted}) {
    muteRequests.add(muted);
  }

  @override
  Future<void> openSystemSettings() async {}

  @override
  void interruptAssistant() {}

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
