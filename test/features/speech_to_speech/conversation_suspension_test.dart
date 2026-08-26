import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_suspension.dart';

void main() {
  test('a zero grace period holds nothing', () {
    final hold = ConversationSuspension(
      gracePeriod: Duration.zero,
      onExpired: () {},
    );
    addTearDown(hold.dispose);

    expect(hold.holdsAnything, isFalse);
  });

  test('a positive grace period can hold a conversation', () {
    final hold = ConversationSuspension(
      gracePeriod: const Duration(seconds: 5),
      onExpired: () {},
    );
    addTearDown(hold.dispose);

    expect(hold.holdsAnything, isTrue);
  });

  test('the timer hangs up after the grace period', () async {
    var expired = 0;
    final hold = ConversationSuspension(
      gracePeriod: const Duration(milliseconds: 40),
      onExpired: () => expired++,
    );
    addTearDown(hold.dispose);

    hold.begin();
    expect(hold.hasLapsed, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(expired, 1);
  });

  test('cancel stops the timer; the clock can still lapse', () async {
    var expired = 0;
    final hold = ConversationSuspension(
      gracePeriod: const Duration(milliseconds: 40),
      onExpired: () => expired++,
    );
    addTearDown(hold.dispose);

    hold
      ..begin()
      ..cancel();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(expired, 0);
    expect(hold.hasLapsed, isTrue);
  });

  test('clear forgets the hold so a later resume is a lapse', () {
    final hold = ConversationSuspension(
      gracePeriod: const Duration(seconds: 5),
      onExpired: () {},
    );
    addTearDown(hold.dispose);

    hold
      ..begin()
      ..clear();

    expect(hold.hasLapsed, isTrue);
  });
}
