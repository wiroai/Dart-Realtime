import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_fields.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_model_badge.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_selector.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// Model and voice metadata attached directly below the app bar title.
///
/// Its layout stays stable throughout the session: model on the left,
/// voice on the right.
class ConversationAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const ConversationAppBarBottom({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final model = viewModel.sessionService.model;
    final voiceField = ConversationFields.voice(model);

    return ValueSelectorBuilder<
      SpeechToSpeechState,
      ({RealtimeSessionState sessionState, bool isReconfiguring})
    >(
      valueListenable: viewModel,
      selector: (state) => (
        sessionState: state.sessionState,
        isReconfiguring: state.isReconfiguring,
      ),
      builder: (context, meta) {
        final stage = meta.sessionState.conversationStage;
        final isLive = stage == ConversationStage.live;
        final liveLayout =
            meta.isReconfiguring || isLive || stage == ConversationStage.ending;
        return SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ProjectSpacing.md,
              0,
              ProjectSpacing.md,
              ProjectSpacing.sm,
            ),
            child: Row(
              key: ValueKey<String>(
                liveLayout ? 'live-app-bar-meta' : 'setup-app-bar-meta',
              ),
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConversationModelBadge(model: model),
                  ),
                ),
                if (voiceField != null)
                  VoiceSelector(
                    field: voiceField,
                    valueListenable: viewModel.parameters.require(
                      voiceField.id,
                    ),
                    enabled: stage == ConversationStage.ready || isLive,
                    loading: meta.isReconfiguring,
                    onSelected: isLive
                        ? (voice) => viewModel.changeVoice(voice).ignore()
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
