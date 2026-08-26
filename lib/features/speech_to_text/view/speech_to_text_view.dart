import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/protocol_event_panel.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/realtime_sliver_app_bar.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/session_controls.dart';
import 'package:wiro_realtime/features/speech_to_text/view/mixin/speech_to_text_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

class SpeechToTextView extends StatefulWidget {
  const SpeechToTextView({
    required this.credentials,
    required this.audioSession,
    required this.sessionGuard,
    this.isVisible = true,
    super.key,
  });

  final WiroCredentials credentials;
  final RealtimeAudioSession audioSession;
  final RealtimeSessionGuard sessionGuard;

  /// Whether this destination is the one on screen.
  ///
  /// The destinations share one widget tree and stay mounted, so a running
  /// transcription would otherwise keep the microphone open and the task
  /// billing behind another tab.
  final bool isVisible;

  @override
  State<SpeechToTextView> createState() => _SpeechToTextViewState();
}

class _SpeechToTextViewState extends State<SpeechToTextView>
    with SpeechToTextViewMixin {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const RealtimeSliverAppBar(title: 'Transcription'),
        SliverPadding(
          padding: ProjectPadding.page,
          sliver: SliverToBoxAdapter(
            child: ValueListenableBuilder<SpeechToTextState>(
              valueListenable: speechToTextViewModel,
              builder: (context, state, _) {
                return SpeechToTextBody(
                  viewModel: speechToTextViewModel,
                  state: state,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class SpeechToTextBody extends StatelessWidget {
  const SpeechToTextBody({
    required this.viewModel,
    required this.state,
    super.key,
  });

  final SpeechToTextViewModel viewModel;
  final SpeechToTextState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FixedModelLabel(model: state.selectedModel),
        const SizedBox(height: 12),
        ModelParameterForm(
          fields: state.selectedModel.firstPassFields,
          values: viewModel.parameters,
          enabled: !state.sessionState.isActive,
        ),
        SessionStatusLabel(sessionState: state.sessionState),
        ElapsedTimeLabel(elapsed: state.elapsed),
        MicrophoneActivityLabel(
          microphoneActive: state.microphoneActive,
        ),
        const SizedBox(height: 8),
        StartStopControls(
          sessionState: state.sessionState,
          startLabel: 'Start',
          stopLabel: 'Stop',
          onStart: viewModel.start,
          onStop: viewModel.stop,
          sessionGuard: viewModel.sessionGuard,
        ),
        if (state.sessionState.isIdleLike)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey<String>('clear-transcript'),
              onPressed: viewModel.clearTranscript,
              child: const Text('Clear transcript'),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          state.transcript.isEmpty
              ? 'Waiting for transcript.'
              : state.transcript,
          style: context.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        SanitizedErrorText(errorMessage: state.errorMessage),
        ProtocolEventPanel(
          expanded: state.protocolExpanded,
          events: state.protocolEvents,
          onToggle: viewModel.toggleProtocolPanel,
        ),
      ],
    );
  }
}
