import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/session_elapsed_clock.dart';

void main() {
  test('reports elapsed time on every tick', () {
    fakeAsync((async) {
      final clock = SessionElapsedClock();
      final ticks = <Duration>[];

      clock.start(ticks.add);
      async.elapse(const Duration(seconds: 3));
      clock.stop();

      expect(ticks, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
      ]);
    });
  });

  test('honours a custom tick cadence', () {
    fakeAsync((async) {
      final clock = SessionElapsedClock(
        tick: const Duration(milliseconds: 250),
      );
      final ticks = <Duration>[];

      clock.start(ticks.add);
      async.elapse(const Duration(milliseconds: 500));
      clock.stop();

      expect(ticks, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ]);
    });
  });

  test('stop halts further ticks', () {
    fakeAsync((async) {
      final clock = SessionElapsedClock();
      final ticks = <Duration>[];

      clock.start(ticks.add);
      async.elapse(const Duration(seconds: 2));
      clock.stop();
      async.elapse(const Duration(seconds: 5));

      expect(ticks, hasLength(2));
      expect(clock.isRunning, isFalse);
    });
  });

  test('restart replaces the previous run without orphaning a timer', () {
    fakeAsync((async) {
      final clock = SessionElapsedClock();
      final first = <Duration>[];
      final second = <Duration>[];

      clock.start(first.add);
      async.elapse(const Duration(seconds: 2));
      clock.start(second.add);
      async.elapse(const Duration(seconds: 2));
      clock.stop();

      expect(first, hasLength(2));
      expect(second, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
      ]);
    });
  });

  test('is idle before start and stop is safe when never started', () {
    final clock = SessionElapsedClock();

    expect(clock.isRunning, isFalse);
    expect(clock.stop, returnsNormally);
  });
}
