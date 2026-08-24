import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Everything a conversation session knows about itself at one moment.
///
/// This is the service's whole output surface. It deliberately excludes purely
/// visual concerns such as whether the protocol panel is expanded; the only
/// concession is [revealProtocolPanel], which reports that a failure produced
/// diagnostics worth showing rather than dictating panel state.
final class ConversationSessionSnapshot extends Equatable {
  const ConversationSessionSnapshot({
    this.status = ViewStatus.initial,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.userTranscript = '',
    this.aiTranscript = '',
    this.microphoneActive = false,
    this.muted = false,
    this.speakerEnabled = true,
    this.isChangingVoice = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.revealProtocolPanel = false,
  });

  final ViewStatus status;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String userTranscript;
  final String aiTranscript;
  final bool microphoneActive;
  final bool muted;
  final bool speakerEnabled;
  final bool isChangingVoice;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool revealProtocolPanel;

  ConversationSessionSnapshot copyWith({
    ViewStatus? status,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? userTranscript,
    String? aiTranscript,
    bool? microphoneActive,
    bool? muted,
    bool? speakerEnabled,
    bool? isChangingVoice,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? revealProtocolPanel,
  }) {
    return ConversationSessionSnapshot(
      status: status ?? this.status,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      userTranscript: userTranscript ?? this.userTranscript,
      aiTranscript: aiTranscript ?? this.aiTranscript,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      muted: muted ?? this.muted,
      speakerEnabled: speakerEnabled ?? this.speakerEnabled,
      isChangingVoice: isChangingVoice ?? this.isChangingVoice,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      protocolEvents: protocolEvents ?? this.protocolEvents,
      revealProtocolPanel: revealProtocolPanel ?? this.revealProtocolPanel,
    );
  }

  @override
  List<Object?> get props => [
    status,
    sessionState,
    elapsed,
    userTranscript,
    aiTranscript,
    microphoneActive,
    muted,
    speakerEnabled,
    isChangingVoice,
    errorMessage,
    protocolEvents,
    revealProtocolPanel,
  ];
}

const Object _unset = Object();
