import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/protocol_event_log.dart';

void main() {
  test('appends events oldest first', () {
    final log = ProtocolEventLog()..add('first');

    final events = log.add('second');

    expect(events, ['first', 'second']);
    expect(log.events, ['first', 'second']);
  });

  test('drops the oldest events past the maximum', () {
    final log = ProtocolEventLog(maximumEvents: 3);

    ['a', 'b', 'c', 'd', 'e'].forEach(log.add);

    expect(log.events, ['c', 'd', 'e']);
  });

  test('never exceeds the default maximum across a long session', () {
    final log = ProtocolEventLog();

    for (var i = 0; i < 500; i++) {
      log.add('event_$i');
    }

    expect(log.events, hasLength(40));
    expect(log.events.first, 'event_460');
    expect(log.events.last, 'event_499');
  });

  test('clear resets the history without breaking later appends', () {
    final log = ProtocolEventLog()
      ..add('stale')
      ..clear();

    expect(log.events, isEmpty);
    expect(log.add('fresh'), ['fresh']);
  });

  test('rejects a non-positive maximum', () {
    expect(() => ProtocolEventLog(maximumEvents: 0), throwsAssertionError);
  });
}
