import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_connect_progress.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// Everything the conversation screen says in words, which is the two
/// things the orb cannot say for itself.
///
/// Waiting names the step it is on and offers a way to abandon it,
/// because that wait runs on someone else's network and a shape that
/// merely stirs cannot tell "coming" from "stuck". Failing states what
/// happened in one line, and a permanently denied microphone gets a way
/// into system settings with it — a silent dead orb is a dead end.
///
/// Everything else is silent. A conversation that is live, or that merely
/// ended, is fully described by the orb above.
class ConversationStageNote extends StatelessWidget {
  const ConversationStageNote({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<
      SpeechToSpeechState,
      ({
        RealtimeSessionState sessionState,
        bool reportsConnecting,
        String? errorMessage,
        bool canOpenSystemSettings,
      })
    >(
      valueListenable: viewModel,
      selector: (state) => (
        sessionState: state.sessionState,
        reportsConnecting: state.reportsConnecting,
        errorMessage: state.errorMessage,
        canOpenSystemSettings: state.canOpenSystemSettings,
      ),
      builder: (context, state) {
        final stage = state.sessionState.conversationStage;
        // `reportsConnecting` is true only between the tap and the first
        // word: a rebuild behind a conversation someone is already having
        // is not news, and there is nothing to cancel that the orb does
        // not already cancel.
        final connecting =
            state.reportsConnecting && stage == ConversationStage.connecting;
        // Height and content are animated separately: the block grows into
        // its new size while the words cross-fade inside it, so the orb
        // above never jumps to make room for a line of text.
        return AnimatedSize(
          duration: ProjectDuration.stageSwap,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: ProjectDuration.stageSwap,
            child: connecting
                ? _ConnectingNote(
                    caption: ConversationConnectProgress.captionFor(
                      state.sessionState,
                    ),
                    onCancel: () => viewModel.stop().ignore(),
                  )
                : stage == ConversationStage.failed &&
                      state.errorMessage != null
                ? _FailureNote(
                    message: state.errorMessage!,
                    onOpenSettings: state.canOpenSystemSettings
                        ? () => viewModel.openSystemSettings().ignore()
                        : null,
                  )
                : const SizedBox(width: double.infinity),
          ),
        );
      },
    );
  }
}

/// The step the connection is on, and the way out of it.
class _ConnectingNote extends StatelessWidget {
  const _ConnectingNote({required this.caption, required this.onCancel});

  final String? caption;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    return Column(
      key: const ValueKey<String>('connect-note'),
      children: [
        const SizedBox(height: ProjectSpacing.md),
        AnimatedSwitcher(
          duration: ProjectDuration.transition,
          child: Text(
            caption ?? '',
            key: ValueKey<String>(caption ?? ''),
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: onCancel,
          child: const Text(ConversationCopy.cancel),
        ),
      ],
    );
  }
}

/// One line under the orb, and an escape hatch only when tapping again
/// cannot possibly help.
class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.message, this.onOpenSettings});

  final String message;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ProjectSpacing.md),
      child: Column(
        children: [
          Text(
            message,
            key: const ValueKey<String>('failure-note'),
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.error,
            ),
          ),
          if (onOpenSettings != null)
            TextButton(
              key: const ValueKey<String>('open-settings-control'),
              onPressed: onOpenSettings,
              child: const Text(ConversationCopy.openSystemSettings),
            ),
        ],
      ),
    );
  }
}
