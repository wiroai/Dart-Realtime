import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/duration_extension.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

/// The recorder's big clock, counting the take.
///
/// Visible for the whole session — a `00:00` during the connect steps is
/// the recorder saying the tape is about to roll — and gone once the
/// session is, because a stale duration under an idle button reads as a
/// recording still running.
class TranscriptionTimer extends StatelessWidget {
  const TranscriptionTimer({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ValueSelectorBuilder<SpeechToTextState, _TimerSelection>(
        valueListenable: viewModel,
        selector: (state) => (
          active: state.sessionState.isActive,
          elapsed: state.elapsed,
        ),
        builder: (context, selection) {
          if (!selection.active) {
            return const SizedBox.shrink();
          }
          return Center(
            child: Text(
              selection.elapsed.clockLabel,
              key: const ValueKey<String>('transcription-timer'),
              style: AppTextStyles.metricLarge.copyWith(
                color: context.colorScheme.onSurface,
                fontFamilyFallback: AppTextStyles.monoFallback,
              ),
            ),
          );
        },
      ),
    );
  }
}

typedef _TimerSelection = ({bool active, Duration elapsed});
