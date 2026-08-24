import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// What the conversation looks like to the person using it.
///
/// [RealtimeSessionState] describes the transport; this describes the
/// screen. The five states between `idle` and `streaming` are one waiting
/// experience, so they collapse into [connecting] and survive only as a
/// progress position.
enum ConversationStage { ready, connecting, live, ending, ended, failed }

extension ConversationStageX on ConversationStage {
  /// True while the session is mid-transition and the primary action
  /// should not be offered again.
  bool get isTransitional =>
      this == ConversationStage.connecting || this == ConversationStage.ending;

  /// True when the orb and transcript belong on screen.
  bool get showsConversation =>
      this == ConversationStage.live || this == ConversationStage.ending;
}

extension ConversationStagePresentation on RealtimeSessionState {
  /// How many states the connecting sequence passes through.
  static const int connectingStepCount = 5;

  ConversationStage get conversationStage => switch (this) {
    RealtimeSessionState.idle => ConversationStage.ready,
    RealtimeSessionState.requestingPermission ||
    RealtimeSessionState.preparingAudio ||
    RealtimeSessionState.creatingTask ||
    RealtimeSessionState.connectingSocket ||
    RealtimeSessionState.waitingForStream => ConversationStage.connecting,
    RealtimeSessionState.streaming => ConversationStage.live,
    RealtimeSessionState.stopping => ConversationStage.ending,
    RealtimeSessionState.completed => ConversationStage.ready,
    RealtimeSessionState.failure => ConversationStage.failed,
  };

  /// One-based position inside the connecting sequence, or `null` for
  /// states that are not part of it.
  int? get connectingStep => switch (this) {
    RealtimeSessionState.requestingPermission => 1,
    RealtimeSessionState.preparingAudio => 2,
    RealtimeSessionState.creatingTask => 3,
    RealtimeSessionState.connectingSocket => 4,
    RealtimeSessionState.waitingForStream => 5,
    RealtimeSessionState.idle ||
    RealtimeSessionState.streaming ||
    RealtimeSessionState.stopping ||
    RealtimeSessionState.completed ||
    RealtimeSessionState.failure => null,
  };
}
