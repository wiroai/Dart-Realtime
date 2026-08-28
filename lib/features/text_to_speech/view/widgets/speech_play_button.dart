import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_ring_button.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view/constants/speech_copy.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

/// The player's transport control: the shared session ring in green.
///
/// Play flips to stop while the voice speaks; the connect and teardown
/// waits wear a spinner.
class SpeechPlayButton extends StatelessWidget {
  const SpeechPlayButton({required this.viewModel, super.key});

  final TextToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeSessionLease?>(
      valueListenable: viewModel.sessionGuard,
      builder: (context, lease, _) {
        return ValueSelectorBuilder<TextToSpeechState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) => SessionRingButton(
            semanticsKey: const ValueKey<String>('tts-play-button'),
            phase: sessionRingPhaseFor(sessionState, busy: lease != null),
            onStart: viewModel.start,
            onStop: viewModel.stop,
            startSemanticLabel: SpeechCopy.playSemanticLabel,
            stopSemanticLabel: SpeechCopy.stopSemanticLabel,
            cancelSemanticLabel: SpeechCopy.cancelSemanticLabel,
            readyIcon: Icons.play_arrow_rounded,
            liveIcon: Icons.stop_rounded,
          ),
        );
      },
    );
  }
}
