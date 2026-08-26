import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_connect_progress.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/state/speech_to_speech_state.dart';

/// The one orb, from the first tap to the last word.
///
/// Every stage of the conversation is a look this widget wears, never a
/// widget that replaces it. That is the whole point of the class: the orb
/// keeps one element, so starting, connecting, listening, answering and
/// stopping are one shape changing rather than five shapes swapped, and
/// the transitions between them can be animated at all.
///
/// It is also the only control the conversation has. Tapping it starts
/// the session; tapping it live pauses capture, or cuts the assistant off
/// while the assistant is the one talking.
class ConversationOrb extends StatelessWidget {
  const ConversationOrb({
    required this.viewModel,
    required this.reportsConnecting,
    required this.onStart,
    super.key,
  });

  final SpeechToSpeechViewModel viewModel;

  /// Whether a connecting transport is worth showing as connecting.
  ///
  /// True only between the tap and the first word. Every other rebuild
  /// is drawn as the live conversation it is, since nobody is waiting on
  /// it and a ring would say the conversation had stopped.
  final bool reportsConnecting;

  /// Begins a conversation. The orb reports the tap rather than starting
  /// the session itself, because the screen has to know a wait was asked
  /// for before it draws one.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<SpeechToSpeechState, _OrbState>(
      valueListenable: viewModel,
      selector: (state) =>
          (paused: state.muted, sessionState: state.sessionState),
      builder: (context, state) {
        return ValueListenableBuilder<RealtimeSessionLease?>(
          valueListenable: viewModel.sessionGuard,
          builder: (context, lease, _) {
            final activity = viewModel.voiceActivity;
            return ListenableBuilder(
              listenable: activity,
              builder: (context, _) => _build(context, state, lease, activity),
            );
          },
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    _OrbState state,
    RealtimeSessionLease? lease,
    ConversationVoiceActivity activity,
  ) {
    // A conversation rebuilding itself still counts as live here: the tap
    // keeps meaning pause or interrupt, and the orb keeps looking like a
    // conversation, because for the person talking it never stopped being
    // one.
    final stage = _stageOf(state.sessionState);
    final live = stage == ConversationStage.live;
    final connecting = stage == ConversationStage.connecting;
    return VoiceOrb(
      key: const ValueKey<String>('conversation-orb'),
      mode: _modeFor(state, stage, activity.phase),
      size: VoiceOrb.sizeFor(context),
      activity: activity,
      progress: _progressFor(state, stage),
      semanticLabel: _semanticLabelFor(state, stage, activity),
      onTap: connecting
          ? null
          : live
          ? () => _tapLive(state, activity)
          // Another feature holding the microphone disables the tap but
          // says nothing: nothing the user did is being refused yet.
          : stage.isTransitional || lease != null
          ? null
          : () {
              HapticFeedback.mediumImpact().ignore();
              onStart();
            },
    );
  }

  void _tapLive(_OrbState state, ConversationVoiceActivity activity) {
    // While the assistant is audible the tap means "shut up", not "pause
    // me": queued speech is cut off and the microphone keeps listening.
    if (!state.paused && activity.aiAudioPending) {
      HapticFeedback.mediumImpact().ignore();
      viewModel.interruptAssistant();
      return;
    }
    HapticFeedback.selectionClick().ignore();
    viewModel.muteChanged(muted: !state.paused);
  }

  VoiceOrbMode _modeFor(
    _OrbState state,
    ConversationStage stage,
    ConversationVoicePhase phase,
  ) {
    return switch (stage) {
      // A failure leaves the orb inviting rather than wearing the failure:
      // the line underneath says what happened, and tapping the same
      // microphone again is the way out of it.
      ConversationStage.ready ||
      ConversationStage.failed => VoiceOrbMode.idle,
      ConversationStage.connecting => VoiceOrbMode.connecting,
      ConversationStage.live || ConversationStage.ending =>
        state.paused
            ? VoiceOrbMode.paused
            : switch (phase) {
                ConversationVoicePhase.userSpeaking =>
                  VoiceOrbMode.userSpeaking,
                ConversationVoicePhase.aiSpeaking => VoiceOrbMode.speaking,
                ConversationVoicePhase.quiet => VoiceOrbMode.listening,
              },
    };
  }

  /// What the screen is showing, which is not always what the transport
  /// is doing: a live conversation whose socket is being rebuilt is still
  /// a live conversation to the person holding the phone.
  ConversationStage _stageOf(RealtimeSessionState sessionState) {
    final stage = sessionState.conversationStage;
    return !reportsConnecting && stage == ConversationStage.connecting
        ? ConversationStage.live
        : stage;
  }

  /// Only the wait before the first word wears a ring, which is why the
  /// stage above is the one the screen shows: a ring around the orb of a
  /// live conversation reads as the conversation being over.
  double? _progressFor(_OrbState state, ConversationStage stage) {
    return stage == ConversationStage.connecting
        ? ConversationConnectProgress.progressFor(state.sessionState)
        : null;
  }

  String? _semanticLabelFor(
    _OrbState state,
    ConversationStage stage,
    ConversationVoiceActivity activity,
  ) {
    if (stage == ConversationStage.connecting) {
      return ConversationCopy.orbConnectingSemanticLabel;
    }
    if (stage != ConversationStage.live) {
      return stage.isTransitional
          ? null
          : ConversationCopy.orbStartSemanticLabel;
    }
    if (state.paused) {
      return ConversationCopy.orbResumeSemanticLabel;
    }
    return activity.aiAudioPending
        ? ConversationCopy.orbSilenceSemanticLabel
        : ConversationCopy.orbPauseSemanticLabel;
  }
}

typedef _OrbState = ({bool paused, RealtimeSessionState sessionState});
