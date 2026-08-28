import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// What the transcription screen actually draws.
///
/// The session's snapshot knows more; a field earns its place here by
/// having a widget that rebuilds on it. The model is not a field at all,
/// because this screen runs against one fixed model.
final class SpeechToTextState extends Equatable {
  const SpeechToTextState({
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.transcript = '',
    this.errorMessage,
  });

  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String transcript;
  final String? errorMessage;

  SpeechToTextState copyWith({
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? transcript,
    Object? errorMessage = _unset,
  }) {
    return SpeechToTextState(
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      transcript: transcript ?? this.transcript,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    sessionState,
    elapsed,
    transcript,
    errorMessage,
  ];
}

const Object _unset = Object();
