import 'package:wiro_realtime/app/constants/session_copy.dart';

/// Every string the conversation screen shows.
///
/// Kept in one place so the wording can be reviewed as copy rather than
/// hunted through the widget tree, and so no session enum name can reach
/// the screen by accident.
///
/// The screen itself contributes almost nothing to this list: it has no
/// heading, no field label and no button caption, and says what it does
/// through the orb alone. What is left here is news the user could not
/// otherwise get — the connect steps and the ways out of them.
abstract final class ConversationCopy {
  static const String cancel = SessionCopy.cancel;
  static const String openSystemSettings = 'Open settings';

  /// What the wait is waiting on, in as few words as the step deserves.
  ///
  /// The ring around the orb already reports progress, so these do not
  /// narrate it. Only the two steps that can stall on something outside
  /// the app get a line of their own; the rest of the wait is plainly
  /// what it is.
  static const String connectingPermission = 'Waiting for microphone access…';
  static const String connectingStream = 'Almost ready…';
  static const String connecting = SessionCopy.connecting;

  static const String orbStartSemanticLabel = 'Start conversation';
  static const String orbConnectingSemanticLabel = 'Connecting';
  static const String orbPauseSemanticLabel = 'Pause conversation';
  static const String orbSilenceSemanticLabel = 'Silence the assistant';
  static const String orbResumeSemanticLabel = 'Resume conversation';
}
