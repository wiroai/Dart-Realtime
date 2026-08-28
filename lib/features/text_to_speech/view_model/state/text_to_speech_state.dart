import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// What the speech screen actually draws.
///
/// The session's snapshot knows more; a field earns its place here by
/// having a widget that rebuilds on it. The model stays because this
/// screen lets the user change it.
final class TextToSpeechState extends Equatable {
  const TextToSpeechState({
    required this.selectedModel,
    this.sessionState = RealtimeSessionState.idle,
    this.isPlaying = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.protocolExpanded = false,
  });

  final ModelDefinition selectedModel;
  final RealtimeSessionState sessionState;
  final bool isPlaying;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool protocolExpanded;

  TextToSpeechState copyWith({
    ModelDefinition? selectedModel,
    RealtimeSessionState? sessionState,
    bool? isPlaying,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? protocolExpanded,
  }) {
    return TextToSpeechState(
      selectedModel: selectedModel ?? this.selectedModel,
      sessionState: sessionState ?? this.sessionState,
      isPlaying: isPlaying ?? this.isPlaying,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      protocolEvents: protocolEvents ?? this.protocolEvents,
      protocolExpanded: protocolExpanded ?? this.protocolExpanded,
    );
  }

  @override
  List<Object?> get props => [
    selectedModel,
    sessionState,
    isPlaying,
    errorMessage,
    protocolEvents,
    protocolExpanded,
  ];
}

const Object _unset = Object();
