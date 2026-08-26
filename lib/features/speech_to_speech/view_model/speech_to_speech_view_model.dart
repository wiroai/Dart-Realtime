import 'dart:async';

import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// Projects a conversation session onto view state.
///
/// Every command is delegated to [sessionService]; this class owns no state
/// of its own and only narrows the session's snapshot to the fields the
/// screen draws.
final class SpeechToSpeechViewModel extends BaseViewModel<SpeechToSpeechState> {
  SpeechToSpeechViewModel({required this.sessionService})
    : super(const SpeechToSpeechState()) {
    _snapshotSubscription = sessionService.snapshots.listen(_applySnapshot);
    // Adopt whatever the session already holds instead of trusting this
    // class's own field defaults to agree with the snapshot's.
    _applySnapshot(sessionService.snapshot);
  }

  final ConversationSessionController sessionService;

  late final StreamSubscription<ConversationSessionSnapshot>
  _snapshotSubscription;

  ModelParameterValues get parameters => sessionService.parameters;

  RealtimeSessionGuard get sessionGuard => sessionService.sessionGuard;

  ConversationVoiceActivity get voiceActivity => sessionService.voiceActivity;

  Future<void> start() => sessionService.start();

  Future<void> stop() => sessionService.stop();

  Future<void> changeVoice(String voice) => sessionService.changeVoice(voice);

  Future<void> applyParameterChanges() =>
      sessionService.applyParameterChanges();

  /// The speaker left the conversation on screen: hold their task quietly
  /// instead of hanging up on them.
  Future<void> suspend() => sessionService.suspend();

  Future<void> resume() => sessionService.resume();

  void muteChanged({required bool muted}) {
    sessionService.setMuted(muted: muted);
  }

  void interruptAssistant() {
    sessionService.interruptAssistant();
  }

  Future<void> openSystemSettings() => sessionService.openSystemSettings();

  @override
  void dispose() {
    unawaited(_snapshotSubscription.cancel());
    unawaited(sessionService.dispose());
    super.dispose();
  }

  void _applySnapshot(ConversationSessionSnapshot snapshot) {
    emit(
      state.copyWith(
        sessionState: snapshot.sessionState,
        muted: snapshot.muted,
        isReconfiguring: snapshot.isReconfiguring,
        errorMessage: snapshot.errorMessage,
        canOpenSystemSettings: snapshot.canOpenSystemSettings,
      ),
    );
  }
}
