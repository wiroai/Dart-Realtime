import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/app/widgets/protocol_event_panel.dart';
import 'package:wiro_realtime/app/widgets/realtime_sliver_app_bar.dart';
import 'package:wiro_realtime/app/widgets/session_controls.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
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
            child: SpeechToTextBody(viewModel: speechToTextViewModel),
          ),
        ),
      ],
    );
  }
}

/// Each section subscribes to the one value it draws, so the transcript
/// streaming in does not redraw the form, and the elapsed clock ticking
/// does not redraw the transcript.
class SpeechToTextBody extends StatelessWidget {
  const SpeechToTextBody({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FixedModelLabel(model: viewModel.model),
        const SizedBox(height: 12),
        ValueSelectorBuilder<SpeechToTextState, bool>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState.isActive,
          builder: (context, active) => ModelParameterForm(
            fields: viewModel.model.firstPassFields,
            values: viewModel.parameters,
            enabled: !active,
          ),
        ),
        ValueSelectorBuilder<SpeechToTextState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) =>
              SessionStatusLabel(sessionState: sessionState),
        ),
        ValueSelectorBuilder<SpeechToTextState, Duration>(
          valueListenable: viewModel,
          selector: (state) => state.elapsed,
          builder: (context, elapsed) => ElapsedTimeLabel(elapsed: elapsed),
        ),
        ValueSelectorBuilder<SpeechToTextState, bool>(
          valueListenable: viewModel,
          selector: (state) => state.microphoneActive,
          builder: (context, active) =>
              MicrophoneActivityLabel(microphoneActive: active),
        ),
        const SizedBox(height: 8),
        ValueSelectorBuilder<SpeechToTextState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) => StartStopControls(
            sessionState: sessionState,
            startLabel: 'Start',
            stopLabel: 'Stop',
            onStart: viewModel.start,
            onStop: viewModel.stop,
            sessionGuard: viewModel.sessionGuard,
          ),
        ),
        ValueSelectorBuilder<SpeechToTextState, bool>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState.isIdleLike,
          builder: (context, idle) => idle
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey<String>('clear-transcript'),
                    onPressed: viewModel.clearTranscript,
                    child: const Text('Clear transcript'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        ValueSelectorBuilder<SpeechToTextState, String>(
          valueListenable: viewModel,
          selector: (state) => state.transcript,
          builder: (context, transcript) => Text(
            transcript.isEmpty ? 'Waiting for transcript.' : transcript,
            style: context.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 12),
        ValueSelectorBuilder<SpeechToTextState, String?>(
          valueListenable: viewModel,
          selector: (state) => state.errorMessage,
          builder: (context, message) =>
              SanitizedErrorText(errorMessage: message),
        ),
        ValueSelectorBuilder<SpeechToTextState, _PanelSelection>(
          valueListenable: viewModel,
          selector: (state) => (
            expanded: state.protocolExpanded,
            events: state.protocolEvents,
          ),
          builder: (context, panel) => ProtocolEventPanel(
            expanded: panel.expanded,
            events: panel.events,
            onToggle: viewModel.toggleProtocolPanel,
          ),
        ),
      ],
    );
  }
}

typedef _PanelSelection = ({bool expanded, List<String> events});
