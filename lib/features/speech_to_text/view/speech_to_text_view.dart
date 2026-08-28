import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/widgets/session_settings_menu.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view/constants/transcription_copy.dart';
import 'package:wiro_realtime/features/speech_to_text/view/mixin/speech_to_text_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_text/view/widgets/transcript_panel.dart';
import 'package:wiro_realtime/features/speech_to_text/view/widgets/transcription_control_strip.dart';
import 'package:wiro_realtime/features/speech_to_text/view/widgets/transcription_mic_button.dart';
import 'package:wiro_realtime/features/speech_to_text/view/widgets/transcription_timer.dart';
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
  static const double _contentMaxWidth = 520;

  // The transcript owns the screen and scrolls inside its own area, so
  // the page itself never scrolls: the record button stays under the
  // thumb no matter how long the text grows.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(TranscriptionCopy.destinationTitle),
        actions: [_AccuracyAction(viewModel: speechToTextViewModel)],
      ),
      body: Padding(
        padding: ProjectPadding.stage,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: SpeechToTextBody(viewModel: speechToTextViewModel),
          ),
        ),
      ),
    );
  }
}

/// Each section subscribes to the one value it draws, so the transcript
/// streaming in does not redraw the controls, and the elapsed clock
/// ticking does not redraw the transcript.
class SpeechToTextBody extends StatelessWidget {
  const SpeechToTextBody({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: TranscriptPanel(viewModel: viewModel)),
        TranscriptionControlStrip(viewModel: viewModel),
        const SizedBox(height: ProjectSpacing.sm),
        TranscriptionTimer(viewModel: viewModel),
        const SizedBox(height: ProjectSpacing.sm),
        Center(child: TranscriptionMicButton(viewModel: viewModel)),
      ],
    );
  }
}

/// The model's speed-versus-accuracy trade, parked in the bar.
///
/// The schema calls it `transcriptionDelay`; a person choosing between
/// "fast" and "accurate" does not need the protocol word for it. The
/// value is sent once when the task starts, so the menu is locked while
/// a session runs.
class _AccuracyAction extends StatelessWidget {
  const _AccuracyAction({required this.viewModel});

  final SpeechToTextViewModel viewModel;

  static const String _fieldId = 'transcriptionDelay';

  ModelFieldDefinition? get _delayField {
    for (final field in viewModel.model.firstPassFields) {
      if (field.id == _fieldId) {
        return field;
      }
    }
    return null;
  }

  String _label(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final field = _delayField;
    if (field == null) {
      return const SizedBox.shrink();
    }
    final valueListenable = viewModel.parameters.require(_fieldId);
    return ValueSelectorBuilder<SpeechToTextState, bool>(
      valueListenable: viewModel,
      selector: (state) => state.sessionState.isIdleLike,
      builder: (context, idle) => ValueListenableBuilder<String>(
        valueListenable: valueListenable,
        builder: (context, value, _) => SessionSettingsMenu(
          menuKey: const ValueKey<String>('transcription-accuracy-menu'),
          tooltip: TranscriptionCopy.accuracyTooltip,
          enabled: idle,
          selectedValue: value,
          options: [
            for (final option in field.options)
              (value: option.value, label: _label(option.value)),
          ],
          onSelected: (next) => valueListenable.value = next,
        ),
      ),
    );
  }
}
