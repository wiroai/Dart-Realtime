import 'dart:async';

import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';

final class FakeConversationSessionController
    implements ConversationSessionController {
  final StreamController<ConversationSessionSnapshot> _snapshots =
      StreamController<ConversationSessionSnapshot>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<String> changeVoiceRequests = [];
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
  Future<void> changeVoice(String voice) async {
    changeVoiceRequests.add(voice);
  }

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
