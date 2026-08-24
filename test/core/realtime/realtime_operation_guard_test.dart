import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_operation_guard.dart';

void main() {
  test('only the newest operation stays current', () {
    final guard = RealtimeOperationGuard();

    final first = guard.begin();
    expect(guard.isCurrent(first), isTrue);

    final second = guard.begin();
    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
    expect(guard.current, second);
  });

  test('an operation id is never reused', () {
    final guard = RealtimeOperationGuard();

    final ids = [for (var i = 0; i < 5; i++) guard.begin()];

    expect(ids, [1, 2, 3, 4, 5]);
  });

  test('disposal invalidates every operation', () {
    final guard = RealtimeOperationGuard()..begin();
    final pending = guard.current;

    guard.dispose();

    expect(guard.isCurrent(pending), isFalse);
    expect(guard.isCurrent(guard.current), isFalse);
    expect(guard.isCurrent(guard.begin()), isFalse);
  });

  test('disposal is reported for callers holding no operation id', () {
    final guard = RealtimeOperationGuard();
    expect(guard.isDisposed, isFalse);

    guard.dispose();

    expect(guard.isDisposed, isTrue);
  });

  test('an unclaimed id is not current before any operation starts', () {
    final guard = RealtimeOperationGuard();

    expect(guard.isCurrent(1), isFalse);
    expect(guard.isCurrent(guard.current), isTrue);
  });
}
