import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_event_parser.dart';

void main() {
  const parser = RealtimeEventParser();

  test('parses known realtime status events', () {
    final event = parser.parse('{"type":"task_stream_ready"}');

    expect(
      event,
      const RealtimeStatusEvent(RealtimeEventType.streamReady),
    );
  });

  test('parses progressive transcript output', () {
    final event = parser.parse(
      '{"type":"task_output","message":"TRANSCRIPT_USER:Hello"}',
    );

    expect(
      event,
      const RealtimeOutputEvent('TRANSCRIPT_USER:Hello'),
    );
  });

  test('does not retain raw server error details', () {
    final event = parser.parse(
      '{"type":"task_error","message":"secret server detail"}',
    );

    expect(event, const RealtimeErrorEvent('task_error'));
    expect(event.toString(), isNot(contains('secret server detail')));
  });

  test('parses binary frames without decoding audio', () {
    final event = parser.parse(Uint8List.fromList([1, 2, 3]));

    expect(event, isA<RealtimeBinaryEvent>());
    expect((event as RealtimeBinaryEvent).bytes, [1, 2, 3]);
  });

  test('keeps unknown event types forward compatible', () {
    final event = parser.parse('{"type":"task_future_event"}');

    expect(event, const RealtimeUnknownEvent('task_future_event'));
  });

  test('maps invalid frames to a malformed event', () {
    expect(parser.parse('not-json'), const RealtimeMalformedEvent());
    expect(
      parser.parse('{"message":"missing type"}'),
      isA<RealtimeMalformedEvent>(),
    );
  });
}
