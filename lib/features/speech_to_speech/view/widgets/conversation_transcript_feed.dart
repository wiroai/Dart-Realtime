import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/transcript_turn.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/transcript_bubble.dart';

/// The conversation as it happens.
class ConversationTranscriptFeed extends StatelessWidget {
  const ConversationTranscriptFeed({required this.turns, super.key});

  final List<TranscriptTurn> turns;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: ProjectDuration.stageSwap,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: turns.isEmpty
          ? const _EmptyFeed()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final turn in turns)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: ProjectSpacing.md,
                    ),
                    child: TranscriptBubble(turn: turn),
                  ),
              ],
            ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ProjectSpacing.md),
      child: Text(
        ConversationCopy.transcriptEmpty,
        textAlign: TextAlign.center,
        style: context.textTheme.bodySmall,
      ),
    );
  }
}
