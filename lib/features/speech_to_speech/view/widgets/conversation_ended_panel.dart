import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/transcript_turn.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_card.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_metric_tile.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_timer.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_transcript_feed.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';

/// What is left after the conversation: how long it ran, what was said,
/// and a way straight back in.
class ConversationEndedPanel extends StatefulWidget {
  const ConversationEndedPanel({
    required this.model,
    required this.elapsed,
    required this.turns,
    required this.onRestart,
    super.key,
  });

  final ModelDefinition model;
  final Duration elapsed;
  final List<TranscriptTurn> turns;
  final VoidCallback onRestart;

  @override
  State<ConversationEndedPanel> createState() => _ConversationEndedPanelState();
}

class _ConversationEndedPanelState extends State<ConversationEndedPanel> {
  bool _transcriptVisible = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: VoiceOrb(
            mode: VoiceOrbMode.ended,
            size: context.dynamicHeight(0.14).clamp(104.0, 140.0),
          ),
        ),
        const SizedBox(height: ProjectSpacing.xl),
        Text(ConversationCopy.summaryEyebrow, style: textTheme.labelSmall),
        const SizedBox(height: ProjectSpacing.sm),
        Text(ConversationCopy.summaryTitle, style: textTheme.headlineSmall),
        const SizedBox(height: ProjectSpacing.lg),
        ConversationCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConversationMetricTile(
                  label: ConversationCopy.durationLabel,
                  value: ConversationTimer(
                    elapsed: widget.elapsed,
                    large: true,
                  ),
                ),
              ),
              Expanded(
                child: ConversationMetricTile(
                  label: ConversationCopy.modelLabel,
                  value: Text(
                    widget.model.displayName,
                    style: AppTextStyles.title.copyWith(
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ProjectSpacing.lg),
        FilledButton.icon(
          key: const ValueKey<String>('start-control'),
          onPressed: () {
            HapticFeedback.mediumImpact().ignore();
            widget.onRestart();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(ConversationCopy.restart),
        ),
        if (widget.turns.isNotEmpty) ...[
          const SizedBox(height: ProjectSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _transcriptVisible = !_transcriptVisible;
              }),
              child: Text(
                _transcriptVisible
                    ? ConversationCopy.hideTranscript
                    : ConversationCopy.showTranscript,
              ),
            ),
          ),
          if (_transcriptVisible)
            ConversationTranscriptFeed(turns: widget.turns),
        ],
      ],
    );
  }
}
