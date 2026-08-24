import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/transcript_turn.dart';

/// One side of the conversation.
///
/// The speaker is carried by alignment, fill, and a label, so the text
/// itself never has to spell out who said it.
class TranscriptBubble extends StatelessWidget {
  const TranscriptBubble({required this.turn, super.key});

  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isYou = turn.speaker == TranscriptSpeaker.you;
    const corner = Radius.circular(ProjectRadius.panel);
    const tight = Radius.circular(ProjectRadius.button);

    return Align(
      alignment: isYou ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dynamicWidth(0.78)),
        child: Column(
          crossAxisAlignment: isYou
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isYou
                  ? ConversationCopy.speakerYou
                  : ConversationCopy.speakerAssistant,
              style: context.textTheme.labelSmall,
            ),
            const SizedBox(height: ProjectSpacing.xs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: isYou
                    ? colorScheme.surfaceContainer
                    : colorScheme.surfaceContainerLowest,
                border: Border.all(
                  color: isYou
                      ? colorScheme.outlineVariant
                      : colorScheme.outline,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: corner,
                  topRight: corner,
                  bottomLeft: isYou ? corner : tight,
                  bottomRight: isYou ? tight : corner,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ProjectSpacing.md - 4,
                  vertical: ProjectSpacing.sm + 2,
                ),
                child: Text(
                  turn.text,
                  style: AppTextStyles.row.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
