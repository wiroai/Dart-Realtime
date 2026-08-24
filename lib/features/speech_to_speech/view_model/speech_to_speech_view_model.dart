import 'dart:async';

import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// Projects a conversation session onto view state.
///
/// Every command is delegated to [sessionService]; the only state this class
/// owns is [SpeechToSpeechState.protocolExpanded], which is a purely visual
/// concern the session has no business knowing about.
final class SpeechToSpeechViewModel extends BaseViewModel<SpeechToSpeechState> {
  SpeechToSpeechViewModel({required this.sessionService})
    : super(SpeechToSpeechState(selectedModel: sessionService.model)) {
    _snapshotSubscription = sessionService.snapshots.listen(_applySnapshot);
    // Adopt whatever the session already holds instead of trusting this
    // class's own field defaults to agree with the snapshot's.
    _applySnapshot(sessionService.snapshot);
  }

  final ConversationSessionController sessionService;

  late final StreamSubscription<ConversationSessionSnapshot>
  _snapshotSubscription;

  /// A failure keeps reporting itself for as long as the session stays failed,
  /// so the panel is revealed only on the edge into that state. Without this
  /// the user could never collapse the panel again.
  bool _protocolPanelRevealed = false;

  ModelParameterValues get parameters => sessionService.parameters;

  RealtimeSessionGuard get sessionGuard => sessionService.sessionGuard;

  Future<void> start() => sessionService.start();

  Future<void> stop() => sessionService.stop();

  Future<void> changeVoice(String voice) => sessionService.changeVoice(voice);

  void muteChanged({required bool muted}) {
    sessionService.setMuted(muted: muted);
  }

  void speakerChanged({required bool enabled}) {
    sessionService.setSpeakerEnabled(enabled: enabled);
  }

  void toggleProtocolPanel() {
    emit(state.copyWith(protocolExpanded: !state.protocolExpanded));
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription.cancel());
    unawaited(sessionService.dispose());
    super.dispose();
  }

  void _applySnapshot(ConversationSessionSnapshot snapshot) {
    final revealNow =
        snapshot.revealProtocolPanel && !_protocolPanelRevealed;
    _protocolPanelRevealed = snapshot.revealProtocolPanel;
    emit(
      state.copyWith(
        status: snapshot.status,
        sessionState: snapshot.sessionState,
        elapsed: snapshot.elapsed,
        userTranscript: snapshot.userTranscript,
        aiTranscript: snapshot.aiTranscript,
        microphoneActive: snapshot.microphoneActive,
        muted: snapshot.muted,
        speakerEnabled: snapshot.speakerEnabled,
        isChangingVoice: snapshot.isChangingVoice,
        errorMessage: snapshot.errorMessage,
        protocolEvents: snapshot.protocolEvents,
        protocolExpanded: revealNow || state.protocolExpanded,
      ),
    );
  }
}
