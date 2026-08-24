import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';

/// Commands a two-way speech conversation and reports it as snapshots.
///
/// The view model depends on this contract rather than on
/// `SpeechToSpeechSessionService` so it can be exercised without audio
/// hardware or a network stack.
abstract interface class ConversationSessionController {
  /// Emits on every session change, synchronously.
  Stream<ConversationSessionSnapshot> get snapshots;

  /// The latest published snapshot.
  ConversationSessionSnapshot get snapshot;

  /// The model this conversation runs against.
  ModelDefinition get model;

  /// Request values sent when the task is created.
  ModelParameterValues get parameters;

  /// Arbitrates which realtime feature owns the audio hardware.
  RealtimeSessionGuard get sessionGuard;

  Future<void> start();

  Future<void> stop();

  void setMuted({required bool muted});

  void setSpeakerEnabled({required bool enabled});

  Future<void> dispose();
}
