import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// What the conversation screen actually draws.
///
/// The session's snapshot knows far more — transcripts, the clock, the
/// protocol log — but the orb-only screen reads none of it, so none of it
/// is projected here. A field earns its place by having a widget that
/// rebuilds on it.
final class SpeechToSpeechState extends Equatable {
  const SpeechToSpeechState({
    this.sessionState = RealtimeSessionState.idle,
    this.muted = false,
    this.isReconfiguring = false,
    this.reportsConnecting = false,
    this.errorMessage,
    this.canOpenSystemSettings = false,
  });

  final RealtimeSessionState sessionState;
  final bool muted;

  /// Whether someone tapped the orb and is still waiting to be heard.
  ///
  /// The connect ring and the line under it belong to that wait and to
  /// nothing else. Every other trip through `connecting` — a dropped
  /// socket, a changed voice, a return from the background, a session
  /// the service restarts on its own after a server error — happens to
  /// someone who did not ask for it and often did not notice, and a ring
  /// around the orb tells them their conversation stopped.
  ///
  /// Raised by the view model's own `start`, never by a session state,
  /// which is the point: no state the service reports can raise a ring
  /// nobody asked for.
  final bool reportsConnecting;

  /// True while the session is tearing down its task and building a new one
  /// with the current parameters, without the user having hung up.
  final bool isReconfiguring;
  final String? errorMessage;

  /// True when [errorMessage] describes something no retry can fix and the
  /// system settings screen can.
  final bool canOpenSystemSettings;

  SpeechToSpeechState copyWith({
    RealtimeSessionState? sessionState,
    bool? muted,
    bool? isReconfiguring,
    bool? reportsConnecting,
    Object? errorMessage = _unset,
    bool? canOpenSystemSettings,
  }) {
    return SpeechToSpeechState(
      sessionState: sessionState ?? this.sessionState,
      muted: muted ?? this.muted,
      isReconfiguring: isReconfiguring ?? this.isReconfiguring,
      reportsConnecting: reportsConnecting ?? this.reportsConnecting,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      canOpenSystemSettings:
          canOpenSystemSettings ?? this.canOpenSystemSettings,
    );
  }

  @override
  List<Object?> get props => [
    sessionState,
    muted,
    isReconfiguring,
    reportsConnecting,
    errorMessage,
    canOpenSystemSettings,
  ];
}

const Object _unset = Object();
