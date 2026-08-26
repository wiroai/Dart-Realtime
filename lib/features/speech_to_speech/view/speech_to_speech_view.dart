import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_fields.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_layout.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/mixin/speech_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/advanced_settings_sheet.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_app_bar_bottom.dart';
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

  // The screen is one orb and at most a line under it, which fits any
  // phone. Nothing here scrolls, so nothing here is a sliver: a scroll
  // view over content that always fits only offers a rubber-band nobody
  // asked for and lets the orb be dragged off its place.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(ConversationCopy.destinationTitle),
        actions: [_AdvancedAction(viewModel: speechToSpeechViewModel)],
        bottom: ConversationAppBarBottom(viewModel: speechToSpeechViewModel),
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

/// The model's engineering parameters, parked in the bar.
///
/// Their natural home is the wait before the orb is tapped, since that is
/// when they are read. Opening the sheet mid-conversation is still allowed:
/// closing it hands the edited values back to the session, which rebuilds
/// its task with them. An untouched form costs nothing either way.
class _AdvancedAction extends StatelessWidget {
  const _AdvancedAction({required this.viewModel});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('advanced-control'),
      onPressed: () {
        showAdvancedSettingsSheet(
          context,
          fields: ConversationFields.advanced(
            viewModel.sessionService.model,
          ),
          values: viewModel.parameters,
        ).then((_) => viewModel.applyParameterChanges()).ignore();
      },
      icon: const Icon(Icons.tune_rounded),
      tooltip: ConversationCopy.advancedToggle,
    );
  }
}

/// The conversation, which is one orb and whatever needs saying under it.
///
/// There are no per-stage panels to swap. Every stage is the same orb in
/// the same place wearing a different look, because a session going live
/// should be watched as one shape settling rather than one screen
/// replacing another — and a shape can only be animated across a change
/// it survives.
class ConversationStageView extends StatefulWidget {
  const ConversationStageView({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  State<ConversationStageView> createState() => _ConversationStageViewState();
}

class _ConversationStageViewState extends State<ConversationStageView> {
  /// Whether someone tapped the orb and is still waiting to be heard.
  ///
  /// The connect ring and the line under it belong to that wait and to
  /// nothing else. Every other trip through `connecting` — a dropped
  /// socket, a changed voice, a return from the background, a session
  /// the service restarts on its own after a server error — happens to
  /// someone who did not ask for it and often did not notice, and a ring
  /// around the orb tells them their conversation stopped.
  ///
  /// Being opened by the tap rather than by a session state is the point:
  /// no state the service reports can raise a ring nobody asked for.
  bool _awaitingFirstWord = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_watchStage);
    _watchStage();
  }

  @override
  void didUpdateWidget(ConversationStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_watchStage);
      widget.viewModel.addListener(_watchStage);
      _watchStage();
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_watchStage);
    super.dispose();
  }

  void _start() {
    setState(() => _awaitingFirstWord = true);
    widget.viewModel.start().ignore();
  }

  void _watchStage() {
    if (!_awaitingFirstWord || !mounted) {
      return;
    }
    // The wait ends when the conversation becomes audible, and equally
    // when it turns out it never will. Only these two stages hold it
    // open, so nothing that happens later can reopen it.
    final holds = switch (widget.viewModel.value.sessionState
        .conversationStage) {
      ConversationStage.ready || ConversationStage.connecting => true,
      ConversationStage.live ||
      ConversationStage.ending ||
      ConversationStage.failed => false,
    };
    if (!holds) {
      setState(() => _awaitingFirstWord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: ConversationLayout.bandAbove(constraints.maxHeight),
          ),
          Center(
            child: ConversationOrb(
              viewModel: widget.viewModel,
              reportsConnecting: _awaitingFirstWord,
              onStart: _start,
            ),
          ),
          ConversationStageNote(
            viewModel: widget.viewModel,
            reportsConnecting: _awaitingFirstWord,
          ),
        ],
      ),
    );
  }
}
