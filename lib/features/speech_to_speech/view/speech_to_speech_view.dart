import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/realtime_sliver_app_bar.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_fields.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/mixin/speech_to_speech_view_mixin.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/advanced_settings_sheet.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_app_bar_bottom.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_live_panel.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_setup_panel.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

class SpeechToSpeechView extends StatefulWidget {
  const SpeechToSpeechView({
    required this.credentials,
    required this.audioSession,
    required this.sessionGuard,
    super.key,
  });

  final WiroCredentials credentials;
  final RealtimeAudioSession audioSession;
  final RealtimeSessionGuard sessionGuard;

  @override
  State<SpeechToSpeechView> createState() => _SpeechToSpeechViewState();
}

class _SpeechToSpeechViewState extends State<SpeechToSpeechView>
    with SpeechToSpeechViewMixin {
  static const double _contentMaxWidth = 520;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        RealtimeSliverAppBar(
          title: ConversationCopy.destinationTitle,
          actions: [_AdvancedAction(viewModel: speechToSpeechViewModel)],
          bottom: ConversationAppBarBottom(
            viewModel: speechToSpeechViewModel,
          ),
        ),
        SliverPadding(
          padding: ProjectPadding.stage,
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _contentMaxWidth,
                ),
                child: ConversationStageSwitcher(
                  viewModel: speechToSpeechViewModel,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The model's engineering parameters, parked in the bar.
///
/// They only mean anything before a session exists, so the control leaves
/// the live call instead of remaining as disabled visual noise.
class _AdvancedAction extends StatelessWidget {
  const _AdvancedAction({required this.viewModel});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('advanced-control'),
      onPressed: () => showAdvancedSettingsSheet(
        context,
        fields: ConversationFields.advanced(
          viewModel.sessionService.model,
        ),
        values: viewModel.parameters,
      ),
      icon: const Icon(Icons.tune_rounded),
      tooltip: ConversationCopy.advancedToggle,
    );
  }
}

/// Shows one stage of the conversation at a time and cross-fades between
/// them.
///
/// Only the stage itself is watched here; every panel subscribes to the
/// finer-grained state it actually draws.
class ConversationStageSwitcher extends StatelessWidget {
  const ConversationStageSwitcher({required this.viewModel, super.key});

  final SpeechToSpeechViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<
      SpeechToSpeechState,
      ({ConversationStage stage, bool isChangingVoice})
    >(
      valueListenable: viewModel,
      selector: (state) => (
        stage: state.sessionState.conversationStage,
        isChangingVoice: state.isChangingVoice,
      ),
      builder: (context, meta) {
        return AnimatedSwitcher(
          duration: ProjectDuration.stageSwap,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey<String>(_panelIdFor(meta)),
            child: _panelFor(meta),
          ),
        );
      },
    );
  }

  Widget _panelFor(({ConversationStage stage, bool isChangingVoice}) meta) {
    if (meta.isChangingVoice) {
      return ConversationLivePanel(viewModel: viewModel);
    }
    return switch (meta.stage) {
      ConversationStage.ready ||
      ConversationStage.connecting ||
      ConversationStage.failed => ConversationSetupPanel(
        viewModel: viewModel,
      ),
      ConversationStage.live ||
      ConversationStage.ending => ConversationLivePanel(viewModel: viewModel),
      ConversationStage.ended => ConversationSetupPanel(viewModel: viewModel),
    };
  }

  String _panelIdFor(({ConversationStage stage, bool isChangingVoice}) meta) {
    if (meta.isChangingVoice) {
      return 'live';
    }
    return switch (meta.stage) {
      ConversationStage.ready ||
      ConversationStage.connecting ||
      ConversationStage.failed ||
      ConversationStage.ended => 'setup',
      ConversationStage.live || ConversationStage.ending => 'live',
    };
  }
}
