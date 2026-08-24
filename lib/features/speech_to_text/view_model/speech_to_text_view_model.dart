import 'dart:async';

import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_controller.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

/// Projects a transcription session onto view state.
///
/// Session commands are delegated to [sessionService]. This class owns only
/// visual state such as whether the protocol panel is expanded.
final class SpeechToTextViewModel extends BaseViewModel<SpeechToTextState> {
  SpeechToTextViewModel({required this.sessionService})
    : super(SpeechToTextState(selectedModel: sessionService.model)) {
    _snapshotSubscription = sessionService.snapshots.listen(_applySnapshot);
    _applySnapshot(sessionService.snapshot);
  }

  final TranscriptionSessionController sessionService;

  late final StreamSubscription<TranscriptionSessionSnapshot>
  _snapshotSubscription;

  bool _protocolPanelRevealed = false;

  ModelParameterValues get parameters => sessionService.parameters;

  RealtimeSessionGuard get sessionGuard => sessionService.sessionGuard;

  Future<void> start() => sessionService.start();

  Future<void> stop() => sessionService.stop();

  void clearTranscript() {
    sessionService.clearTranscript();
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

  void _applySnapshot(TranscriptionSessionSnapshot snapshot) {
    final revealNow = snapshot.revealProtocolPanel && !_protocolPanelRevealed;
    _protocolPanelRevealed = snapshot.revealProtocolPanel;
    emit(
      state.copyWith(
        status: snapshot.status,
        sessionState: snapshot.sessionState,
        elapsed: snapshot.elapsed,
        transcript: snapshot.transcript,
        microphoneActive: snapshot.microphoneActive,
        errorMessage: snapshot.errorMessage,
        protocolEvents: snapshot.protocolEvents,
        protocolExpanded: revealNow || state.protocolExpanded,
      ),
    );
  }
}
