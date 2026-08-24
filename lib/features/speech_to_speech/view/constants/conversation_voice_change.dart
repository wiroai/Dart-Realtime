import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Voice-change progress uses the three transport states that remain after
/// audio is already prepared.
abstract final class ConversationVoiceChange {
  static const int stepCount = 3;

  static double progressFor(RealtimeSessionState state) {
    final step = switch (state) {
      RealtimeSessionState.creatingTask => 1,
      RealtimeSessionState.connectingSocket => 2,
      RealtimeSessionState.waitingForStream => 3,
      _ => 0,
    };
    if (step == 0) {
      return 0;
    }
    return step / stepCount;
  }
}
