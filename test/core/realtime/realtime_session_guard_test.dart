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

  test('acquireWhenFree acquires immediately when nothing is held', () async {
    final guard = RealtimeSessionGuard();
    addTearDown(guard.dispose);

    final lease = await guard.acquireWhenFree(
      RealtimeSessionOwner.conversation,
    );

    expect(lease, isNotNull);
    expect(guard.value, same(lease));
  });

  test('acquireWhenFree waits out the departing session', () async {
    final guard = RealtimeSessionGuard();
    addTearDown(guard.dispose);
    final departing = guard.acquire(RealtimeSessionOwner.conversation);

    final pending = guard.acquireWhenFree(
      RealtimeSessionOwner.transcription,
    );
    guard.release(departing);

    final lease = await pending;
    expect(lease, isNotNull);
    expect(lease!.owner, RealtimeSessionOwner.transcription);
    expect(guard.value, same(lease));
  });

  test('acquireWhenFree gives up once nothing lets go', () async {
    final guard = RealtimeSessionGuard();
    addTearDown(guard.dispose);
    guard.acquire(RealtimeSessionOwner.conversation);

    final lease = await guard.acquireWhenFree(
      RealtimeSessionOwner.speech,
      timeout: const Duration(milliseconds: 20),
    );

    expect(lease, isNull);
  });

  test('disposal wakes a pending acquireWhenFree with nothing', () async {
    final guard = RealtimeSessionGuard()
      ..acquire(RealtimeSessionOwner.conversation);

    final pending = guard.acquireWhenFree(
      RealtimeSessionOwner.speech,
    );
    guard.dispose();

    expect(await pending, isNull);
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
