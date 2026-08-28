import 'package:wiro_realtime/app/constants/session_copy.dart';

/// Every string the speech screen shows.
///
/// Kept in one place so the wording can be reviewed as copy rather than
/// hunted through the widget tree, and so no session enum name can reach
/// the screen by accident.
abstract final class SpeechCopy {
  static const String destinationTitle = 'Speech';

  static const String promptHint =
      'Type or paste the text to speak.\nTap play when you are ready.';

  static const String connecting = SessionCopy.connecting;
  static const String buffering = 'Buffering…';
  static const String speaking = 'Speaking…';
  static const String finishing = SessionCopy.finishing;

  static const String modelTooltip = 'Model';

  static const String playSemanticLabel = 'Play speech';
  static const String stopSemanticLabel = 'Stop speech';
  static const String cancelSemanticLabel = SessionCopy.cancel;

  static String characterCount(int count) => '$count characters';
}
