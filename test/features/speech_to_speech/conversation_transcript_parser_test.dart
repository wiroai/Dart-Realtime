import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_transcript_parser.dart';

void main() {
  const parser = ConversationTranscriptParser();

  test('assigns a prefixed user line to the user', () {
    final transcript = parser.parse('TRANSCRIPT_USER:hello there');

    expect(transcript, isA<UserTranscript>());
    expect(transcript?.text, 'hello there');
  });

  test('assigns a prefixed assistant line to the assistant', () {
    final transcript = parser.parse('TRANSCRIPT_AI:how can I help');

    expect(transcript, isA<AiTranscript>());
    expect(transcript?.text, 'how can I help');
  });

  test('returns null for output that is not a transcript', () {
    expect(parser.parse('task cost: 0.01'), isNull);
    expect(parser.parse(''), isNull);
  });

  test('keeps the payload verbatim, including colons and whitespace', () {
    final transcript = parser.parse('TRANSCRIPT_AI: sure: 10:30 works ');

    expect(transcript?.text, ' sure: 10:30 works ');
  });

  test('an empty payload yields an empty transcript rather than null', () {
    final transcript = parser.parse('TRANSCRIPT_USER:');

    expect(transcript, isA<UserTranscript>());
    expect(transcript?.text, isEmpty);
  });

  test('a prefix in the middle of a message is not a transcript', () {
    expect(parser.parse('log TRANSCRIPT_USER:hello'), isNull);
  });
}
