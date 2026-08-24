import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_binary_frame.dart';

void main() {
  test('encodes and decodes a token-prefixed PCM frame', () {
    final payload = Uint8List.fromList([1, 2, 3]);

    final frame = RealtimeBinaryFrame.encode(
      taskToken: 'task-token',
      payload: payload,
    );

    expect(frame, [...utf8.encode('task-token|'), 1, 2, 3]);
    expect(
      RealtimeBinaryFrame.decodePayload(
        taskToken: 'task-token',
        frame: frame,
      ),
      payload,
    );
  });

  test('rejects a binary frame for another task token', () {
    final frame = RealtimeBinaryFrame.encode(
      taskToken: 'other-token',
      payload: Uint8List.fromList([1, 2, 3]),
    );

    expect(
      RealtimeBinaryFrame.decodePayload(
        taskToken: 'task-token',
        frame: frame,
      ),
      isNull,
    );
  });
}
