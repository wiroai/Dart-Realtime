import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_status_strip.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view/constants/transcription_copy.dart';
import 'package:wiro_realtime/features/speech_to_text/view/widgets/transcription_wave.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

/// The strip above the record button: the shared status strip wearing
/// the recorder's words, and the waveform while the microphone streams.
class TranscriptionControlStrip extends StatelessWidget {
  const TranscriptionControlStrip({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  /// Only the permission ask can stall on something outside the app, so
  /// only it gets a line of its own; the rest of the connect is plainly
  /// what it is.
  static const SessionStripCopy _copy = SessionStripCopy(
    requestingPermission: TranscriptionCopy.connectingPermission,
    preparingAudio: TranscriptionCopy.connecting,
    creatingTask: TranscriptionCopy.connecting,
    connectingSocket: TranscriptionCopy.connecting,
    waitingForStream: TranscriptionCopy.connecting,
    stopping: TranscriptionCopy.finishing,
  );

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<SpeechToTextState, _StripSelection>(
      valueListenable: viewModel,
      selector: (state) => (
        sessionState: state.sessionState,
        errorMessage: state.errorMessage,
      ),
      builder: (context, selection) => SessionStatusStrip(
        sessionState: selection.sessionState,
        copy: _copy,
        streaming: const TranscriptionWave(),
        errorMessage: selection.errorMessage,
        errorKey: const ValueKey<String>('transcription-error'),
      ),
    );
  }
}

typedef _StripSelection = ({
  RealtimeSessionState sessionState,
  String? errorMessage,
});
