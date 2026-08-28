import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_ring_button.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view/constants/transcription_copy.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

/// The recorder's record button: the shared session ring in red.
///
/// The shape language every recorder app shares — a red circle to start,
/// the circle collapsing into a square to stop, pulse rings while it is
/// live.
class TranscriptionMicButton extends StatelessWidget {
  const TranscriptionMicButton({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeSessionLease?>(
      valueListenable: viewModel.sessionGuard,
      builder: (context, lease, _) {
        return ValueSelectorBuilder<SpeechToTextState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) => SessionRingButton(
            semanticsKey: const ValueKey<String>('transcription-mic-button'),
            phase: sessionRingPhaseFor(sessionState, busy: lease != null),
            onStart: viewModel.start,
            onStop: viewModel.stop,
            startSemanticLabel: TranscriptionCopy.micStartSemanticLabel,
            stopSemanticLabel: TranscriptionCopy.micStopSemanticLabel,
            cancelSemanticLabel: TranscriptionCopy.micCancelSemanticLabel,
            accent: context.colorScheme.error,
            collapseWhenLive: true,
            pulseWhenLive: true,
          ),
        );
      },
    );
  }
}
