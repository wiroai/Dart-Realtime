import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

final class SpeechToTextState extends Equatable {
  const SpeechToTextState({
    this.status = ViewStatus.initial,
    this.selectedModel = WiroModelCatalog.voxtralMiniRealtime,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.transcript = '',
    this.microphoneActive = false,
    this.errorMessage,
    this.protocolEvents = const [],
    this.protocolExpanded = false,
  });

  final ViewStatus status;
  final ModelDefinition selectedModel;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String transcript;
  final bool microphoneActive;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool protocolExpanded;

  SpeechToTextState copyWith({
    ViewStatus? status,
    ModelDefinition? selectedModel,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? transcript,
    bool? microphoneActive,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? protocolExpanded,
  }) {
    return SpeechToTextState(
      status: status ?? this.status,
      selectedModel: selectedModel ?? this.selectedModel,
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
    status,
    selectedModel,
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
