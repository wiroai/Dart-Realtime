import 'package:wiro_realtime/app/constants/session_copy.dart';

/// Every string the transcription screen shows.
///
/// Kept in one place so the wording can be reviewed as copy rather than
/// hunted through the widget tree, and so no session enum name can reach
/// the screen by accident.
abstract final class TranscriptionCopy {
  static const String destinationTitle = 'Transcription';

  static const String emptyTranscript =
      'Tap record and start speaking.\nWords appear here as you talk.';

  static const String copyAction = 'Copy';
  static const String clearAction = 'Clear';
  static const String copiedToast = 'Transcript copied';

  /// What the wait is waiting on. Only the step that can stall on
  /// something outside the app gets a line of its own.
  static const String connectingPermission = 'Waiting for microphone access…';
  static const String connecting = SessionCopy.connecting;
  static const String finishing = SessionCopy.finishing;

  static const String accuracyTooltip = 'Accuracy';

  static const String micStartSemanticLabel = 'Start recording';
  static const String micStopSemanticLabel = 'Stop recording';
  static const String micCancelSemanticLabel = SessionCopy.cancel;
}
