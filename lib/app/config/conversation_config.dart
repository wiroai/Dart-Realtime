import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';

/// The conversation, in one place.
///
/// This is the file to edit to turn the example into a product. Everything
/// else — the transport, the audio pipeline, the screen — stays as it is.
///
/// The values here win over the catalog's own defaults, which describe the
/// model rather than this app's use of it.
abstract final class ConversationConfig {
  /// Who the assistant is and how it should behave.
  ///
  /// The two sentences about language are worth keeping whatever else is
  /// written here: they let a speaker switch languages mid-conversation and
  /// stop the model from inventing words out of background noise.
  static const String persona =
      'Respond in the language of the latest clear spoken utterance. '
      'Allow intentional language changes. Ignore non-speech or '
      'unclear audio instead of inferring words.';

  /// Which voice answers. The full list lives in [WiroModelCatalog].
  static const String voice = 'marin';

  /// Which Wiro model runs the conversation.
  static const ModelDefinition model = WiroModelCatalog.gptRealtimeMini;

  /// The engineering parameters, for the developer who needs them.
  ///
  /// Everything [model] accepts beyond the persona and the voice — the
  /// transcription model, audio formats and rates, turn detection — is
  /// listed with its options in [WiroModelCatalog]. A key named here
  /// replaces that catalog default when the task is created; anything
  /// left out keeps it. Keys are the catalog's field ids, values are
  /// their string form.
  ///
  /// [persona] and [voice] have their own fields above and win over
  /// entries here, so this map cannot silently contradict them.
  static const Map<String, String> parameters = {
    // 'transcription_model': 'whisper-1',
    // 'turn_detection_threshold': '0.6',
    // 'turn_detection_silence_ms': '400',
  };

  /// How long one conversation may run before it ends itself.
  ///
  /// A live session is a billed Wiro task and a phone can sit in a pocket
  /// with the microphone open, so the example refuses to run forever. Set
  /// it to [Duration.zero] to remove the ceiling.
  static const Duration maxSessionDuration = Duration(minutes: 10);

  /// How long a conversation is held for a speaker who left the screen,
  /// before it ends itself.
  ///
  /// Zero — leave the screen and the conversation is over — because Wiro
  /// bills a realtime task by how long it stays up, not by how much is said
  /// into it. A held task is a meter running for someone who is not there.
  /// The server takes the same view and stops a task that has gone quiet on
  /// its own, so a long hold cannot be relied on anyway.
  ///
  /// Raising it buys continuity: returning within the window rejoins the
  /// same task, and the assistant still remembers the conversation instead
  /// of starting over as a stranger. Keep it well under the server's own
  /// silence timeout — currently around twenty seconds — or the hold ends in
  /// a dead task and a wasted charge.
  static const Duration suspendGracePeriod = Duration.zero;
}
