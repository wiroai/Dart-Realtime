import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/app/widgets/protocol_event_panel.dart';
import 'package:wiro_realtime/app/widgets/realtime_sliver_app_bar.dart';
import 'package:wiro_realtime/app/widgets/session_controls.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view/mixin/text_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/state/text_to_speech_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

class TextToSpeechView extends StatefulWidget {
  const TextToSpeechView({
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
  /// speech task would otherwise keep playing and billing behind another
  /// tab.
  final bool isVisible;

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
            child: TextToSpeechBody(viewModel: textToSpeechViewModel),
          ),
        ),
      ],
    );
  }
}

/// Each section subscribes to the one value it draws, so the elapsed
/// clock ticking does not redraw the form, and typing into the prompt
/// does not redraw anything but the character count.
class TextToSpeechBody extends StatelessWidget {
  const TextToSpeechBody({required this.viewModel, super.key});

  final TextToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueSelectorBuilder<TextToSpeechState, _ModelSelection>(
          valueListenable: viewModel,
          selector: (state) => (
            model: state.selectedModel,
            active: state.sessionState.isActive,
          ),
          builder: (context, selection) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TtsModelSelector(
                viewModel: viewModel,
                selectedModel: selection.model,
                enabled: !selection.active,
              ),
              const SizedBox(height: 12),
              ModelParameterForm(
                key: ValueKey<String>(selection.model.modelSlug),
                fields: selection.model.firstPassFields,
                values: viewModel.parameters,
                enabled: !selection.active,
              ),
            ],
          ),
        ),
        TtsCharacterCount(viewModel: viewModel),
        ValueSelectorBuilder<TextToSpeechState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) =>
              SessionStatusLabel(sessionState: sessionState),
        ),
        ValueSelectorBuilder<TextToSpeechState, Duration>(
          valueListenable: viewModel,
          selector: (state) => state.elapsed,
          builder: (context, elapsed) => ElapsedTimeLabel(elapsed: elapsed),
        ),
        ValueSelectorBuilder<TextToSpeechState, bool>(
          valueListenable: viewModel,
          selector: (state) => state.isPlaying,
          builder: (context, playing) => Text(playing ? 'Playing' : 'Idle'),
        ),
        const SizedBox(height: 8),
        ValueSelectorBuilder<TextToSpeechState, RealtimeSessionState>(
          valueListenable: viewModel,
          selector: (state) => state.sessionState,
          builder: (context, sessionState) => StartStopControls(
            sessionState: sessionState,
            startLabel: 'Play',
            stopLabel: 'Stop',
            onStart: viewModel.start,
            onStop: viewModel.stop,
            sessionGuard: viewModel.sessionGuard,
          ),
        ),
        const SizedBox(height: 12),
        ValueSelectorBuilder<TextToSpeechState, String?>(
          valueListenable: viewModel,
          selector: (state) => state.errorMessage,
          builder: (context, message) =>
              SanitizedErrorText(errorMessage: message),
        ),
        ValueSelectorBuilder<TextToSpeechState, _PanelSelection>(
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

typedef _ModelSelection = ({ModelDefinition model, bool active});

typedef _PanelSelection = ({bool expanded, List<String> events});

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
