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
    this.microphoneActive = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.protocolExpanded = false,
  });

  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String transcript;
  final bool microphoneActive;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool protocolExpanded;

  SpeechToTextState copyWith({
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? transcript,
    bool? microphoneActive,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? protocolExpanded,
  }) {
    return SpeechToTextState(
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      transcript: transcript ?? this.transcript,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      protocolEvents: protocolEvents ?? this.protocolEvents,
      protocolExpanded: protocolExpanded ?? this.protocolExpanded,
    );
  }

  @override
  List<Object?> get props => [
    sessionState,
    elapsed,
    transcript,
    microphoneActive,
    errorMessage,
    protocolEvents,
    protocolExpanded,
  ];
}

const Object _unset = Object();
