import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

final class SpeechToSpeechState extends Equatable {
  const SpeechToSpeechState({
    required this.selectedModel,
    this.status = ViewStatus.initial,
    this.sessionState = RealtimeSessionState.idle,
    this.elapsed = Duration.zero,
    this.userTranscript = '',
    this.aiTranscript = '',
    this.microphoneActive = false,
    this.muted = false,
    this.speakerEnabled = true,
    this.errorMessage,
    this.protocolEvents = const [],
    this.protocolExpanded = false,
  });

  final ViewStatus status;
  final ModelDefinition selectedModel;
  final RealtimeSessionState sessionState;
  final Duration elapsed;
  final String userTranscript;
  final String aiTranscript;
  final bool microphoneActive;
  final bool muted;
  final bool speakerEnabled;
  final String? errorMessage;
  final List<String> protocolEvents;
  final bool protocolExpanded;

  SpeechToSpeechState copyWith({
    ViewStatus? status,
    ModelDefinition? selectedModel,
    RealtimeSessionState? sessionState,
    Duration? elapsed,
    String? userTranscript,
    String? aiTranscript,
    bool? microphoneActive,
    bool? muted,
    bool? speakerEnabled,
    Object? errorMessage = _unset,
    List<String>? protocolEvents,
    bool? protocolExpanded,
  }) {
    return SpeechToSpeechState(
      status: status ?? this.status,
      selectedModel: selectedModel ?? this.selectedModel,
      sessionState: sessionState ?? this.sessionState,
      elapsed: elapsed ?? this.elapsed,
      userTranscript: userTranscript ?? this.userTranscript,
      aiTranscript: aiTranscript ?? this.aiTranscript,
      microphoneActive: microphoneActive ?? this.microphoneActive,
      muted: muted ?? this.muted,
      speakerEnabled: speakerEnabled ?? this.speakerEnabled,
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
    userTranscript,
    aiTranscript,
    microphoneActive,
    muted,
    speakerEnabled,
    errorMessage,
    protocolEvents,
    protocolExpanded,
  ];
}

const Object _unset = Object();
