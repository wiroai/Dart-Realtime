import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_layout.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// Everything before the conversation is audible, which is now almost
/// nothing: who is speaking, in which voice, and the orb.
///
/// There is no heading and no button caption. What the screen is for is
/// carried by the app-bar metadata and by a microphone that moves until
/// it is pressed.
///
/// Waiting for the connection is not a screen of its own either. The orb
/// stays exactly where it was tapped and closes a ring around itself, so
/// the five transport states read as one gesture completing rather than a
/// second page arriving.
class ConversationSetupPanel extends StatelessWidget {
  const ConversationSetupPanel({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<SpeechToSpeechState, RealtimeSessionState>(
      valueListenable: viewModel,
      selector: (state) => state.sessionState,
      builder: (context, sessionState) {
        final connecting =
            sessionState.conversationStage == ConversationStage.connecting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ConversationLayout.contentBand(context),
            ),
            _StartControl(
              viewModel: viewModel,
              sessionState: sessionState,
              connecting: connecting,
            ),
          ],
        );
      },
    );
  }
}

/// The orb doing double duty: the button that starts the session and the
/// indicator that reports how far it has got.
class _StartControl extends StatelessWidget {
  const _StartControl({
    required this.viewModel,
    required this.sessionState,
    required this.connecting,
  });

  final SpeechToSpeechViewModel viewModel;
  final RealtimeSessionState sessionState;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeSessionLease?>(
      valueListenable: viewModel.sessionGuard,
      builder: (context, lease, _) {
        final blocked = lease != null && !connecting;
        final note = _note(blocked: blocked);
        return Column(
          children: [
            VoiceOrb(
              key: const ValueKey<String>('start-control'),
              mode: connecting ? VoiceOrbMode.connecting : VoiceOrbMode.idle,
              size: VoiceOrb.sizeFor(context),
              progress: connecting ? _progress : null,
              semanticLabel: connecting
                  ? ConversationCopy.orbConnectingSemanticLabel
                  : ConversationCopy.orbStartSemanticLabel,
              onTap: connecting || blocked
                  ? null
                  : () {
                      HapticFeedback.mediumImpact().ignore();
                      viewModel.start().ignore();
                    },
            ),
            // Nothing here while the orb is idle: it says what it wants by
            // moving. Text appears only when there is news the animation
            // cannot carry.
            if (note != null) ...[
              const SizedBox(height: ProjectSpacing.md),
              Text(
                note,
                key: const ValueKey<String>('start-control-label'),
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall,
              ),
            ],
            if (connecting)
              TextButton(
                onPressed: () => viewModel.stop().ignore(),
                child: const Text(ConversationCopy.cancel),
              ),
          ],
        );
      },
    );
  }

  String? _note({required bool blocked}) {
    if (connecting) {
      return ConversationCopy.connectingStepLabel(sessionState);
    }
    return blocked ? ConversationCopy.sessionBusy : null;
  }

  /// Each transport state closes another slice of the ring, so the circle
  /// completing and the conversation starting are the same event.
  double get _progress {
    final step = sessionState.connectingStep ?? 0;
    return step / ConversationStagePresentation.connectingStepCount;
  }
}
