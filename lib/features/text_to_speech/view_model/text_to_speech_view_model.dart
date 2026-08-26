import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_controller.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_snapshot.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';

/// Projects a text-to-speech session onto view state.
final class TextToSpeechViewModel extends BaseViewModel<TextToSpeechState> {
  TextToSpeechViewModel({required this.sessionService})
    : super(
        TextToSpeechState(
          selectedModel: sessionService.snapshot.selectedModel,
        ),
      ) {
    _snapshotSubscription = sessionService.snapshots.listen(_applySnapshot);
    _applySnapshot(sessionService.snapshot);
  }

  final SpeechSessionController sessionService;

  late final StreamSubscription<SpeechSessionSnapshot> _snapshotSubscription;

  bool _protocolPanelRevealed = false;

  ModelParameterValues get parameters => sessionService.parameters;

  RealtimeSessionGuard get sessionGuard => sessionService.sessionGuard;

  ValueNotifier<String> get promptNotifier {
    return sessionService.promptNotifier;
  }

  void selectModel(ModelDefinition model) {
    sessionService.selectModel(model);
  }

  Future<void> start() => sessionService.start();

  Future<void> stop() => sessionService.stop();

  void toggleProtocolPanel() {
    emit(state.copyWith(protocolExpanded: !state.protocolExpanded));
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription.cancel());
    unawaited(sessionService.dispose());
    super.dispose();
  }

  void _applySnapshot(SpeechSessionSnapshot snapshot) {
    final revealNow = snapshot.revealProtocolPanel && !_protocolPanelRevealed;
    _protocolPanelRevealed = snapshot.revealProtocolPanel;
    emit(
      state.copyWith(
        selectedModel: snapshot.selectedModel,
        sessionState: snapshot.sessionState,
        elapsed: snapshot.elapsed,
        isPlaying: snapshot.isPlaying,
        errorMessage: snapshot.errorMessage,
        protocolEvents: snapshot.protocolEvents,
        protocolExpanded: revealNow || state.protocolExpanded,
      ),
    );
  }
}
