import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// Every string the conversation screen shows.
///
/// Kept in one place so the wording can be reviewed as copy rather than
/// hunted through the widget tree, and so no session enum name can reach
/// the screen by accident.
///
/// The setup screen contributes nothing to this list: it has no heading,
/// no field label and no button caption, and says what it does through
/// two pills and a moving microphone. What is left here is news the user
/// could not otherwise get — progress, failures, and the summary.
abstract final class ConversationCopy {
  static const String destinationTitle = 'Conversation';
  static const String sessionBusy = 'Another session is running';
  static const String advancedToggle = 'Advanced settings';
  static const String advancedTitle = 'Advanced settings';
  static const String advancedSubtitle =
      'Parameters sent to the model when the session is created.';
  static const String advancedDone = 'Done';

  static const String cancel = 'Cancel';

  static const String transcriptEmpty = 'Listening…';
  static const String speakerYou = 'You';
  static const String speakerAssistant = 'Assistant';

  static const String summaryEyebrow = 'SESSION SUMMARY';
  static const String summaryTitle = 'Conversation ended.';
  static const String durationLabel = 'Duration';
  static const String modelLabel = 'Model';
  static const String restart = 'Start new conversation';
  static const String showTranscript = 'View transcript';
  static const String hideTranscript = 'Hide transcript';

  static const String failureTitle = 'The conversation stopped.';
  static const String retry = 'Try again';
  static const String showDetails = 'Technical details';
  static const String hideDetails = 'Hide technical details';

  static const String orbStartSemanticLabel = 'Start conversation';
  static const String orbConnectingSemanticLabel = 'Connecting';
  static const String orbPauseSemanticLabel = 'Pause conversation';
  static const String orbResumeSemanticLabel = 'Resume conversation';

  /// What the person is waiting for right now.
  ///
  /// Returns an empty string outside the connecting sequence; callers only
  /// reach this while the connecting stage is on screen.
  static String connectingStepLabel(RealtimeSessionState state) {
    return switch (state) {
      RealtimeSessionState.requestingPermission => 'Waiting for microphone',
      RealtimeSessionState.preparingAudio => 'Preparing microphone',
      RealtimeSessionState.creatingTask => 'Creating session',
      RealtimeSessionState.connectingSocket => 'Connecting',
      RealtimeSessionState.waitingForStream => 'Almost ready',
      RealtimeSessionState.idle ||
      RealtimeSessionState.streaming ||
      RealtimeSessionState.stopping ||
      RealtimeSessionState.completed ||
      RealtimeSessionState.failure => '',
    };
  }
}
