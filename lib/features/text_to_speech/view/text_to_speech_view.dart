import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_settings_menu.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/view/constants/speech_copy.dart';
import 'package:wiro_realtime/features/text_to_speech/view/mixin/text_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/text_to_speech/view/widgets/speech_play_button.dart';
import 'package:wiro_realtime/features/text_to_speech/view/widgets/speech_prompt_editor.dart';
import 'package:wiro_realtime/features/text_to_speech/view/widgets/speech_status_strip.dart';
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
  static const double _contentMaxWidth = 520;

  // The editor owns the screen and scrolls inside its own area, so the
  // page itself never scrolls: the play button stays under the thumb no
  // matter how long the text grows.
  @override
  Widget build(BuildContext context) {
    // Read above this view's own Scaffold, which consumes the inset and
    // hides it from the body. While the keyboard is up the writer is
    // writing, so the play controls yield their space to the text.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text(SpeechCopy.destinationTitle),
        actions: [
          _ModelAction(viewModel: textToSpeechViewModel),
        ],
      ),
      // The editor fills the screen, so the only place a thumb can land
      // to put the keyboard away is the control area below it; a tap
      // there should read as "done typing" rather than be swallowed.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Padding(
          padding: ProjectPadding.stage,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: TextToSpeechBody(
                viewModel: textToSpeechViewModel,
                keyboardOpen: keyboardOpen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each section subscribes to the one value it draws, so a session state
/// change does not redraw the editor, and typing into the prompt does
/// not redraw anything but the character count.
class TextToSpeechBody extends StatelessWidget {
  const TextToSpeechBody({
    required this.viewModel,
    this.keyboardOpen = false,
    super.key,
  });

  final TextToSpeechViewModel viewModel;

  /// Whether the software keyboard is on screen.
  ///
  /// The controls below the editor hide behind it rather than squeeze
  /// the text into whatever sliver the keyboard leaves; a session cannot
  /// start mid-edit anyway, so nothing tappable is lost.
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ValueSelectorBuilder<TextToSpeechState, _EditorSelection>(
            valueListenable: viewModel,
            selector: (state) => (
              modelSlug: state.selectedModel.modelSlug,
              active: state.sessionState.isActive,
            ),
            builder: (context, selection) => SpeechPromptEditor(
              // A new model brings a new parameter set, so the editor
              // re-binds to the new prompt notifier.
              key: ValueKey<String>('tts-editor-${selection.modelSlug}'),
              promptNotifier: viewModel.promptNotifier,
              enabled: !selection.active,
            ),
          ),
        ),
        if (!keyboardOpen) ...[
          SpeechStatusStrip(viewModel: viewModel),
          const SizedBox(height: ProjectSpacing.sm),
          Center(child: SpeechPlayButton(viewModel: viewModel)),
        ],
      ],
    );
  }
}

typedef _EditorSelection = ({String modelSlug, bool active});

/// The voice model, parked in the bar the way settings are.
///
/// The value is sent once when the task starts, so the menu is locked
/// while a session runs.
class _ModelAction extends StatelessWidget {
  const _ModelAction({required this.viewModel});

  final TextToSpeechViewModel viewModel;

  static const List<ModelDefinition> _models = [
    WiroModelCatalog.mossTtsRealtime,
    WiroModelCatalog.voxcpm2,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<TextToSpeechState, _ModelSelection>(
      valueListenable: viewModel,
      selector: (state) => (
        modelSlug: state.selectedModel.modelSlug,
        idle: state.sessionState.isIdleLike,
      ),
      builder: (context, selection) => SessionSettingsMenu(
        menuKey: const ValueKey<String>('tts-model-selector'),
        tooltip: SpeechCopy.modelTooltip,
        enabled: selection.idle,
        selectedValue: selection.modelSlug,
        options: [
          for (final model in _models)
            (value: model.modelSlug, label: model.displayName),
        ],
        onSelected: (slug) {
          for (final model in _models) {
            if (model.modelSlug == slug) {
              viewModel.selectModel(model);
              return;
            }
          }
        },
      ),
    );
  }
}

typedef _ModelSelection = ({String modelSlug, bool idle});
