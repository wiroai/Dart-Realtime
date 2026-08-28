import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/mixin/speech_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_app_bar_title.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_orb.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_stage_note.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

class SpeechToSpeechView extends StatefulWidget {
  const SpeechToSpeechView({
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
  /// The destinations share one widget tree and stay mounted, so a live
  /// conversation would otherwise keep the microphone open and the task
  /// billing behind another tab.
  final bool isVisible;

  @override
  State<SpeechToSpeechView> createState() => _SpeechToSpeechViewState();
}

class _SpeechToSpeechViewState extends State<SpeechToSpeechView>
    with SpeechToSpeechViewMixin {
  static const double _contentMaxWidth = 520;

  // The screen is one orb and at most a line over it, which fits any
  // phone. Nothing here scrolls, so nothing here is a sliver: a scroll
  // view over content that always fits only offers a rubber-band nobody
  // asked for and lets the orb be dragged off its place.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ConversationAppBarTitle(viewModel: speechToSpeechViewModel),
      ),
      body: Padding(
        padding: ProjectPadding.stage,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: ConversationStageView(viewModel: speechToSpeechViewModel),
          ),
        ),
      ),
    );
  }
}

/// The conversation, which is one orb and whatever needs saying over it.
///
/// There are no per-stage panels to swap. Every stage is the same orb in
/// the same place wearing a different look, because a session going live
/// should be watched as one shape settling rather than one screen
/// replacing another — and a shape can only be animated across a change
/// it survives.
///
/// The orb sits where every tab's button sits — at the bottom, under the
/// thumb — with the stage note above it the way the other tabs' status
/// strips are. Anchoring it to the bottom is also what keeps it in one
/// place: the note grows upward into the empty stage instead of pushing
/// the orb anywhere.
class ConversationStageView extends StatelessWidget {
  const ConversationStageView({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        ConversationStageNote(viewModel: viewModel),
        const SizedBox(height: ProjectSpacing.sm),
        Center(child: ConversationOrb(viewModel: viewModel)),
      ],
    );
  }
}
