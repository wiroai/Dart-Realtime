import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// What the conversation looks like to the person using it.
///
/// [RealtimeSessionState] describes the transport; this describes the
/// screen. The five states between `idle` and `streaming` are one waiting
/// experience, so they collapse into [connecting]; the orb's warming-up
/// motion carries the wait without naming any of them.
enum ConversationStage { ready, connecting, live, ending, failed }

extension ConversationStageX on ConversationStage {
  /// True while the session is mid-transition and the primary action
  /// should not be offered again.
  bool get isTransitional =>
      this == ConversationStage.connecting || this == ConversationStage.ending;
}

extension ConversationStagePresentation on RealtimeSessionState {
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
}
