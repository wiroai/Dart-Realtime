import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Everything a text-to-speech session knows at one moment.
final class SpeechSessionSnapshot extends Equatable {
  const SpeechSessionSnapshot({
    required this.selectedModel,
    this.status = ViewStatus.initial,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.isPlaying = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.revealProtocolPanel = false,
  });

  final ViewStatus status;
  final ModelDefinition selectedModel;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final bool isPlaying;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool revealProtocolPanel;

  SpeechSessionSnapshot copyWith({
    ViewStatus? status,
    ModelDefinition? selectedModel,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    bool? isPlaying,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? revealProtocolPanel,
  }) {
    return SpeechSessionSnapshot(
      status: status ?? this.status,
      selectedModel: selectedModel ?? this.selectedModel,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      isPlaying: isPlaying ?? this.isPlaying,
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
    selectedModel,
    sessionState,
    elapsed,
    isPlaying,
    errorMessage,
    protocolEvents,
    revealProtocolPanel,
  ];
}

const Object _unset = Object();
