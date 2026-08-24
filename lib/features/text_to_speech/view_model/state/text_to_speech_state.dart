import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

final class TextToSpeechState extends Equatable {
  const TextToSpeechState({
    this.status = ViewStatus.initial,
    this.selectedModel = WiroModelCatalog.mossTtsRealtime,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.isPlaying = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.protocolExpanded = false,
  });

  final ViewStatus status;
  final ModelDefinition selectedModel;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final bool isPlaying;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool protocolExpanded;

  TextToSpeechState copyWith({
    ViewStatus? status,
    ModelDefinition? selectedModel,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    bool? isPlaying,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? protocolExpanded,
  }) {
    return TextToSpeechState(
      status: status ?? this.status,
      selectedModel: selectedModel ?? this.selectedModel,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
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
    status,
    selectedModel,
    sessionState,
    elapsed,
    isPlaying,
    errorMessage,
    protocolEvents,
    protocolExpanded,
  ];
}

const Object _unset = Object();
