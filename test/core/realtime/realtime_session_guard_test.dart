import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';

void main() {
  test('allows one lease and rejects parallel sessions', () {
    final guard = RealtimeSessionGuard();
    addTearDown(guard.dispose);

    final conversation = guard.acquire(
      RealtimeSessionOwner.conversation,
    );
    final transcription = guard.acquire(
      RealtimeSessionOwner.transcription,
    );

    expect(conversation, isNotNull);
    expect(transcription, isNull);
    expect(guard.value, same(conversation));
  });

  test('only the current lease can release the guard', () {
    final guard = RealtimeSessionGuard();
    addTearDown(guard.dispose);

    final first = guard.acquire(RealtimeSessionOwner.speech);
    guard.release(first);
    final second = guard.acquire(RealtimeSessionOwner.speech);

    guard.release(first);

    expect(guard.value, same(second));
  });

  test('ignores asynchronous release after disposal', () {
    final guard = RealtimeSessionGuard();
    final lease = guard.acquire(RealtimeSessionOwner.conversation);

    guard.dispose();

    expect(() => guard.release(lease), returnsNormally);
    expect(
      guard.acquire(RealtimeSessionOwner.transcription),
      isNull,
    );
  });
}
