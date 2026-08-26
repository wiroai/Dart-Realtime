import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';

/// The wait between the tap and the first audible word, told as five
/// steps.
///
/// The five transport states before `streaming` are one experience to
/// live through but not one thing to look at: permission can hang on a
/// system dialog and a cold task can take seconds, so an orb that only
/// stirs leaves no way to tell a session that is coming from one that is
/// stuck. Each step advances the ring and names itself in plain words.
abstract final class ConversationConnectProgress {
  /// How far round the ring each step stands.
  ///
  /// The first step is already a fifth of the way in, so the tap itself
  /// is what visibly moves the ring; the last stops just short of closing
  /// it, because a full circle would promise a conversation that has not
  /// started. Only the first audible word closes it, by which point the
  /// orb is live and the ring is gone.
  static const List<double> _stops = [0.2, 0.4, 0.6, 0.8, 0.94];

  static double? progressFor(RealtimeSessionState state) {
    final step = _stepFor(state);
    return step == 0 ? null : _stops[step - 1];
  }

  static String? captionFor(RealtimeSessionState state) {
    return switch (state) {
      // The permission dialog is the one step the app is not the one
      // holding up, and the last step is the one worth being patient for.
      RealtimeSessionState.requestingPermission =>
        ConversationCopy.connectingPermission,
      RealtimeSessionState.waitingForStream =>
        ConversationCopy.connectingStream,
      RealtimeSessionState.preparingAudio ||
      RealtimeSessionState.creatingTask ||
      RealtimeSessionState.connectingSocket => ConversationCopy.connecting,
      _ => null,
    };
  }

  static int _stepFor(RealtimeSessionState state) {
    return switch (state) {
      RealtimeSessionState.requestingPermission => 1,
      RealtimeSessionState.preparingAudio => 2,
      RealtimeSessionState.creatingTask => 3,
      RealtimeSessionState.connectingSocket => 4,
      RealtimeSessionState.waitingForStream => 5,
      _ => 0,
    };
  }
}
