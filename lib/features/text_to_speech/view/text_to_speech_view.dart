import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/protocol_event_panel.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/realtime_sliver_app_bar.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/session_controls.dart';
import 'package:wiro_realtime/features/text_to_speech/view/mixin/text_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

class TextToSpeechView extends StatefulWidget {
  const TextToSpeechView({
    required this.credentials,
    required this.audioSession,
    required this.sessionGuard,
    super.key,
  });

  final WiroCredentials credentials;
  final RealtimeAudioSession audioSession;
  final RealtimeSessionGuard sessionGuard;

  @override
  State<TextToSpeechView> createState() => _TextToSpeechViewState();
}

class _TextToSpeechViewState extends State<TextToSpeechView>
    with TextToSpeechViewMixin {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const RealtimeSliverAppBar(title: 'Speech'),
        SliverPadding(
          padding: ProjectPadding.page,
          sliver: SliverToBoxAdapter(
            child: ValueListenableBuilder<TextToSpeechState>(
              valueListenable: textToSpeechViewModel,
              builder: (context, state, _) {
                return TextToSpeechBody(
                  viewModel: textToSpeechViewModel,
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

class TextToSpeechBody extends StatelessWidget {
  const TextToSpeechBody({
    required this.viewModel,
    required this.state,
    super.key,
  });

  final TextToSpeechViewModel viewModel;
  final TextToSpeechState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TtsModelSelector(
          viewModel: viewModel,
          selectedModel: state.selectedModel,
          enabled: !state.sessionState.isActive,
        ),
        const SizedBox(height: 12),
        ModelParameterForm(
          key: ValueKey<String>(state.selectedModel.modelSlug),
          fields: state.selectedModel.firstPassFields,
          values: viewModel.parameters,
          enabled: !state.sessionState.isActive,
        ),
        TtsCharacterCount(viewModel: viewModel),
        SessionStatusLabel(sessionState: state.sessionState),
        ElapsedTimeLabel(elapsed: state.elapsed),
        Text(state.isPlaying ? 'Playing' : 'Idle'),
        const SizedBox(height: 8),
        StartStopControls(
          sessionState: state.sessionState,
          startLabel: 'Play',
          stopLabel: 'Stop',
          onStart: viewModel.start,
          onStop: viewModel.stop,
          sessionGuard: viewModel.sessionGuard,
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

class TtsModelSelector extends StatelessWidget {
  const TtsModelSelector({
    required this.viewModel,
    required this.selectedModel,
    required this.enabled,
    super.key,
  });

  final TextToSpeechViewModel viewModel;
  final ModelDefinition selectedModel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const models = [WiroModelCatalog.mossTtsRealtime];
    return DropdownButtonFormField<String>(
      key: const ValueKey<String>('tts-model-selector'),
      initialValue: selectedModel.modelSlug,
      items: [
        for (final model in models)
          DropdownMenuItem<String>(
            value: model.modelSlug,
            child: Text(model.displayName),
          ),
      ],
      onChanged: enabled
          ? (slug) {
              for (final model in models) {
                if (model.modelSlug == slug) {
                  viewModel.selectModel(model);
                  return;
                }
              }
            }
          : null,
      decoration: const InputDecoration(labelText: 'Model'),
    );
  }
}

class TtsCharacterCount extends StatelessWidget {
  const TtsCharacterCount({required this.viewModel, super.key});

  final TextToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: viewModel.promptNotifier,
      builder: (context, value, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Text('${value.length} characters'),
        );
      },
    );
  }
}
