import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_layout.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_voice_change.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// The screen while the conversation is running.
///
/// The session is represented by one control. Tapping the orb pauses or
/// resumes capture without closing the realtime connection.
class ConversationLivePanel extends StatelessWidget {
  const ConversationLivePanel({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final band = ConversationLayout.contentBand(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: band),
        Center(child: _LiveOrb(viewModel: viewModel)),
      ],
    );
  }
}

class _LiveOrb extends StatelessWidget {
  const _LiveOrb({required this.viewModel});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<
      SpeechToSpeechState,
      ({
        bool paused,
        bool changingVoice,
        ConversationStage stage,
        RealtimeSessionState sessionState,
      })
    >(
      valueListenable: viewModel,
      selector: (state) => (
        paused: state.muted,
        changingVoice: state.isChangingVoice,
        stage: state.sessionState.conversationStage,
        sessionState: state.sessionState,
      ),
      builder: (context, state) {
        final switching = state.changingVoice;
        final mode = switching
            ? VoiceOrbMode.connecting
            : state.paused
            ? VoiceOrbMode.paused
            : VoiceOrbMode.listening;
        return VoiceOrb(
          key: const ValueKey<String>('live-orb-control'),
          mode: mode,
          size: VoiceOrb.sizeFor(context),
          progress: switching
              ? ConversationVoiceChange.progressFor(state.sessionState)
              : null,
          semanticLabel: switching
              ? ConversationCopy.orbConnectingSemanticLabel
              : state.stage == ConversationStage.live
              ? state.paused
                    ? ConversationCopy.orbResumeSemanticLabel
                    : ConversationCopy.orbPauseSemanticLabel
              : null,
          onTap: !switching && state.stage == ConversationStage.live
              ? () {
                  HapticFeedback.selectionClick().ignore();
                  viewModel.muteChanged(muted: !state.paused);
                }
              : null,
        );
      },
    );
  }
}
