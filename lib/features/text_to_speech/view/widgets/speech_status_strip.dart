import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_status_strip.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view/constants/speech_copy.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

/// The strip above the play button: the shared status strip wearing the
/// player's words, and — while audio streams — whether the voice is
/// audible yet.
class SpeechStatusStrip extends StatelessWidget {
  const SpeechStatusStrip({required this.viewModel, super.key});

  final TextToSpeechViewModel viewModel;

  static const SessionStripCopy _copy = SessionStripCopy(
    requestingPermission: SpeechCopy.connecting,
    preparingAudio: SpeechCopy.connecting,
    creatingTask: SpeechCopy.connecting,
    connectingSocket: SpeechCopy.connecting,
    waitingForStream: SpeechCopy.connecting,
    stopping: SpeechCopy.finishing,
  );

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<TextToSpeechState, _StripSelection>(
      valueListenable: viewModel,
      selector: (state) => (
        sessionState: state.sessionState,
        isPlaying: state.isPlaying,
        errorMessage: state.errorMessage,
      ),
      builder: (context, selection) => SessionStatusStrip(
        sessionState: selection.sessionState,
        copy: _copy,
        streaming: Text(
          selection.isPlaying ? SpeechCopy.speaking : SpeechCopy.buffering,
          style: SessionStatusStrip.mutedStyle(context),
        ),
        errorMessage: selection.errorMessage,
        errorKey: const ValueKey<String>('tts-error'),
      ),
    );
  }
}

typedef _StripSelection = ({
  RealtimeSessionState sessionState,
  bool isPlaying,
  String? errorMessage,
});
