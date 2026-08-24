import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/protocol_event_panel.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/session_controls.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/mixin/speech_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

class SpeechToSpeechView extends StatefulWidget {
  const SpeechToSpeechView({
    required this.credentials,
    required this.audioSession,
    required this.sessionGuard,
    super.key,
  });

  final WiroCredentials credentials;
  final RealtimeAudioSession audioSession;
  final RealtimeSessionGuard sessionGuard;

  @override
  State<SpeechToSpeechView> createState() => _SpeechToSpeechViewState();
}

class _SpeechToSpeechViewState extends State<SpeechToSpeechView>
    with SpeechToSpeechViewMixin {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: ProjectPadding.page,
          sliver: SliverToBoxAdapter(
            child: ValueListenableBuilder<SpeechToSpeechState>(
              valueListenable: speechToSpeechViewModel,
              builder: (context, state, _) {
                return SpeechToSpeechBody(
                  viewModel: speechToSpeechViewModel,
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

class SpeechToSpeechBody extends StatelessWidget {
  const SpeechToSpeechBody({
    required this.viewModel,
    required this.state,
    super.key,
  });

  final SpeechToSpeechViewModel viewModel;
  final SpeechToSpeechState state;

  @override
  Widget build(BuildContext context) {
    final formEnabled = !state.sessionState.isActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Conversation'),
        const SizedBox(height: 8),
        FixedModelLabel(model: state.selectedModel),
        const SizedBox(height: 12),
        ModelParameterForm(
          fields: state.selectedModel.firstPassFields,
          values: viewModel.parameters,
          enabled: formEnabled,
        ),
        SessionStatusLabel(sessionState: state.sessionState),
        ElapsedTimeLabel(elapsed: state.elapsed),
        MicrophoneActivityLabel(
          microphoneActive: state.microphoneActive,
        ),
        const SizedBox(height: 8),
        SpeechToSpeechLocalControls(viewModel: viewModel, state: state),
        const SizedBox(height: 8),
        StartStopControls(
          sessionState: state.sessionState,
          startLabel: 'Start',
          stopLabel: 'Stop',
          onStart: viewModel.start,
          onStop: viewModel.stop,
          sessionGuard: viewModel.sessionGuard,
        ),
        const SizedBox(height: 12),
        const Text('User transcript'),
        SpeechTranscriptText(
          value: state.userTranscript,
          emptyLabel: 'Waiting for user speech.',
        ),
        const SizedBox(height: 12),
        const Text('AI transcript'),
        SpeechTranscriptText(
          value: state.aiTranscript,
          emptyLabel: 'Waiting for assistant speech.',
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

class SpeechToSpeechLocalControls extends StatelessWidget {
  const SpeechToSpeechLocalControls({
    required this.viewModel,
    required this.state,
    super.key,
  });

  final SpeechToSpeechViewModel viewModel;
  final SpeechToSpeechState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilterChip(
          key: const ValueKey<String>('mute-control'),
          label: Text(state.muted ? 'Muted' : 'Mute'),
          selected: state.muted,
          onSelected: (value) => viewModel.muteChanged(muted: value),
        ),
        const SizedBox(width: 8),
        FilterChip(
          key: const ValueKey<String>('speaker-control'),
          label: Text(
            state.speakerEnabled ? 'Speaker on' : 'Speaker off',
          ),
          selected: state.speakerEnabled,
          onSelected: (value) {
            viewModel.speakerChanged(enabled: value);
          },
        ),
      ],
    );
  }
}

class SpeechTranscriptText extends StatelessWidget {
  const SpeechTranscriptText({
    required this.value,
    required this.emptyLabel,
    super.key,
  });

  final String value;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Text(value.isEmpty ? emptyLabel : value);
  }
}
