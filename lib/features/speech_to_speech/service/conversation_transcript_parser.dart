/// A transcript line together with the speaker it belongs to.
sealed class ConversationTranscript {
  const ConversationTranscript(this.text);

  final String text;
}

final class UserTranscript extends ConversationTranscript {
  const UserTranscript(super.text);
}

final class AiTranscript extends ConversationTranscript {
  const AiTranscript(super.text);
}

/// Recognises the speaker prefixes the conversation model puts on its
/// transcript output.
///
/// The realtime protocol carries both speakers over the same output channel,
/// so the prefix is the only thing that tells them apart.
final class ConversationTranscriptParser {
  const ConversationTranscriptParser();

  static const String userPrefix = 'TRANSCRIPT_USER:';
  static const String aiPrefix = 'TRANSCRIPT_AI:';

  /// Returns `null` for output that is not a transcript at all.
  ConversationTranscript? parse(String message) {
    if (message.startsWith(userPrefix)) {
      return UserTranscript(message.substring(userPrefix.length));
    }
    if (message.startsWith(aiPrefix)) {
      return AiTranscript(message.substring(aiPrefix.length));
    }
    return null;
  }
}
