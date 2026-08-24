import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Everything a transcription session knows about itself at one moment.
///
/// Visual state is excluded. [revealProtocolPanel] only reports that fresh
/// failure diagnostics are available for the view to reveal.
final class TranscriptionSessionSnapshot extends Equatable {
  const TranscriptionSessionSnapshot({
    this.status = ViewStatus.initial,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.transcript = '',
    this.microphoneActive = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.revealProtocolPanel = false,
  });

  final ViewStatus status;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String transcript;
  final bool microphoneActive;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool revealProtocolPanel;

  TranscriptionSessionSnapshot copyWith({
    ViewStatus? status,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? transcript,
    bool? microphoneActive,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? revealProtocolPanel,
  }) {
    return TranscriptionSessionSnapshot(
      status: status ?? this.status,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      transcript: transcript ?? this.transcript,
      microphoneActive: microphoneActive ?? this.microphoneActive,
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
    transcript,
    microphoneActive,
    errorMessage,
    protocolEvents,
    revealProtocolPanel,
  ];
}

const Object _unset = Object();
