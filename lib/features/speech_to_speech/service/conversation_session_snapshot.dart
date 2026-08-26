import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Everything a conversation session knows about itself at one moment.
///
/// This is the service's whole output surface, and it deliberately excludes
/// purely visual concerns: the view model narrows it to what the screen
/// draws. Transcripts and the clock live here because the session needs them
/// — a reconnect preserves what was said, the limit watches the clock — and
/// because tests read the session through this surface alone.
final class ConversationSessionSnapshot extends Equatable {
  const ConversationSessionSnapshot({
    this.status = ViewStatus.initial,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.userTranscript = '',
    this.aiTranscript = '',
    this.microphoneActive = false,
    this.muted = false,
    this.isReconfiguring = false,
    this.isSuspended = false,
    this.errorMessage,
    this.canOpenSystemSettings = false,
    this.protocolEvents = const [],
  });

  final ViewStatus status;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String userTranscript;
  final String aiTranscript;
  final bool microphoneActive;
  final bool muted;

  /// True while the session is tearing down its task and building a new one
  /// with the current parameters, without the user having hung up.
  final bool isReconfiguring;

  /// True while the speaker is away and the task is being held for them:
  /// the microphone is off, nothing is billed to the transcript, and the
  /// conversation is one return away from continuing.
  final bool isSuspended;
  final String? errorMessage;

  /// True when [errorMessage] describes something no retry can fix and the
  /// system settings screen can.
  final bool canOpenSystemSettings;
  final List<String> protocolEvents;

  ConversationSessionSnapshot copyWith({
    ViewStatus? status,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? userTranscript,
    String? aiTranscript,
    bool? microphoneActive,
    bool? muted,
    bool? isReconfiguring,
    bool? isSuspended,
    Object? errorMessage = _unset,
    bool? canOpenSystemSettings,
    List<String>? protocolEvents,
  }) {
    return ConversationSessionSnapshot(
      status: status ?? this.status,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      userTranscript: userTranscript ?? this.userTranscript,
      aiTranscript: aiTranscript ?? this.aiTranscript,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      muted: muted ?? this.muted,
      isReconfiguring: isReconfiguring ?? this.isReconfiguring,
      isSuspended: isSuspended ?? this.isSuspended,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      canOpenSystemSettings:
          canOpenSystemSettings ?? this.canOpenSystemSettings,
      protocolEvents: protocolEvents ?? this.protocolEvents,
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
    isReconfiguring,
    isSuspended,
    errorMessage,
    canOpenSystemSettings,
    protocolEvents,
  ];
}

const Object _unset = Object();
