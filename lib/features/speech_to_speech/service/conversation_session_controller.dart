import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';

/// Commands a two-way speech conversation and reports it as snapshots.
///
/// The view model depends on this contract rather than on
/// `SpeechToSpeechSessionService` so it can be exercised without audio
/// hardware or a network stack.
///
/// Every command is a no-op once [dispose] has run. Teardown races with the
/// widget lifecycle, so a late command is an expected condition rather than a
/// caller error.
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

  /// Live microphone and playback levels for the conversation orb.
  ConversationVoiceActivity get voiceActivity;

  Future<void> start();

  Future<void> stop();

  Future<void> changeVoice(String voice);

  /// Silences the microphone and lets go of the audio hardware because the
  /// speaker left the screen, while holding their task open for a short
  /// while so [resume] can continue the same conversation.
  ///
  /// Nobody hung up here, so the task is not ended: a new one would cost
  /// another launch and would leave the assistant with no memory of what
  /// was already said. The hold is bounded, and once it lapses the session
  /// ends itself as if the user had stopped it.
  Future<void> suspend();

  /// Brings a [suspend]ed conversation back, reconnecting to the held task
  /// when it is still alive and starting a fresh one when it is not.
  Future<void> resume();

  void setMuted({required bool muted});

  /// Silences the assistant mid-answer on the user's explicit request:
  /// queued audio is flushed and the rest of the turn is discarded, while
  /// the microphone keeps listening.
  void interruptAssistant();

  /// Sends the user to the system settings page for this app, which is the
  /// only way out of a permanently denied microphone.
  Future<void> openSystemSettings();

  Future<void> dispose();
}
