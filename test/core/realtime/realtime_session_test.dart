import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_socket_client.dart';

void main() {
  test('subscribes exactly once and waits for stream readiness', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);

    final connecting = session.connect();
    await pumpEventQueue();

    expect(socket.connectCalls, 1);
    expect(socket.sentText, hasLength(1));
    expect(jsonDecode(socket.sentText.single), {
      'type': 'task_info',
      'tasktoken': 'task-token',
    });

    socket.emit('{"type":"task_stream_ready"}');
    await connecting;
    await session.connect();

    expect(session.isReady, isTrue);
    expect(socket.connectCalls, 1);
    expect(socket.sentText, hasLength(1));
    await session.close();
  });

  test('emits output and unknown events after ready', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final events = <RealtimeEvent>[];
    final subscription = session.events.listen(events.add);
    addTearDown(subscription.cancel);

    final connecting = session.connect();
    await pumpEventQueue();
    socket
      ..emit('{"type":"task_stream_ready"}')
      ..emit('{"type":"task_output","message":"TRANSCRIPT_USER:Hi"}')
      ..emit('{"type":"task_future_event"}');
    await connecting;

    expect(
      events,
      contains(const RealtimeOutputEvent('TRANSCRIPT_USER:Hi')),
    );
    expect(
      events,
      contains(const RealtimeUnknownEvent('task_future_event')),
    );
    await session.close();
  });

  test('prefixes PCM audio with the task token', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    final sent = session.sendAudio(Uint8List.fromList([1, 2, 3]));

    expect(sent, isTrue);
    expect(socket.sentBinary.single, [
      ...utf8.encode('task-token|'),
      1,
      2,
      3,
    ]);
    await session.close();
  });

  test('strips and validates the token from server audio', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final events = <RealtimeEvent>[];
    final subscription = session.events.listen(events.add);
    addTearDown(subscription.cancel);
    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    socket.emit(
      Uint8List.fromList([
        ...utf8.encode('task-token|'),
        1,
        2,
        3,
      ]),
    );

    expect(
      events.whereType<RealtimeBinaryEvent>().single.bytes,
      [1, 2, 3],
    );
    expect(session.metrics.framesProcessed, 2);
    expect(session.metrics.binaryFrames, 1);
    expect(session.metrics.malformedFrames, 0);
    await session.close();
  });

  test('accepts server audio prefixed with the task id', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final events = <RealtimeEvent>[];
    final subscription = session.events.listen(events.add);
    addTearDown(subscription.cancel);
    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    socket.emit(
      Uint8List.fromList([
        ...utf8.encode('2743770|'),
        4,
        5,
        6,
      ]),
    );

    expect(
      events.whereType<RealtimeBinaryEvent>().single.bytes,
      [4, 5, 6],
    );
    await session.close();
  });

  test('closes idempotently on postprocess completion', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);

    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    socket.emit('{"type":"task_postprocess_end"}');
    await pumpEventQueue();
    await session.close();

    expect(session.isClosed, isTrue);
    expect(socket.closeCalls, 1);
  });

  test('a task_error log frame keeps the session alive', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final received = <RealtimeEvent>[];
    final subscription = session.events.listen(received.add);
    addTearDown(subscription.cancel);

    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    // Wiro documents the live task_error frame as interim stderr output:
    // the task may still succeed, so only a socket closure is terminal.
    socket.emit(
      '{"type":"task_error","message":"private server detail"}',
    );
    await pumpEventQueue();

    expect(session.isReady, isTrue);
    expect(session.isClosed, isFalse);
    expect(received, contains(const RealtimeErrorEvent('task_error')));
    await session.close();
  });

  test('maps server cancellation before stream readiness', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);
    final connecting = expectLater(
      session.connect(),
      throwsA(isA<WiroCancellationFailure>()),
    );
    await pumpEventQueue();

    socket.emit('{"type":"task_cancel"}');
    await connecting;
    await pumpEventQueue();

    expect(session.isClosed, isTrue);
    expect(socket.closeCalls, 1);
  });

  test('sends task_session_end once during early stop', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);

    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;

    await session.stop();
    await session.stop();

    final frames = socket.sentText.map(jsonDecode).toList();
    expect(
      frames.where(
        (frame) =>
            frame is Map<String, dynamic> &&
            frame['type'] == 'task_session_end',
      ),
      hasLength(1),
    );
    expect(frames.last, {
      'type': 'task_session_end',
      'tasktoken': 'task-token',
    });
  });

  test('closes when stream readiness times out', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(
      socket,
      readyTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      session.connect(),
      throwsA(isA<WiroReadyTimeoutFailure>()),
    );

    expect(session.isClosed, isTrue);
    expect(socket.closeCalls, 1);
  });

  test('does not reconnect after remote disconnect', () async {
    final socket = FakeRealtimeSocketClient();
    addTearDown(socket.dispose);
    final session = createSession(socket);

    final connecting = session.connect();
    await pumpEventQueue();
    socket.emit('{"type":"task_stream_ready"}');
    await connecting;
    await socket.finish();
    await pumpEventQueue();

    await session.connect();

    expect(socket.connectCalls, 1);
    expect(session.isClosed, isTrue);
  });
}

RealtimeSession createSession(
  RealtimeSocketClient socket, {
  Duration readyTimeout = const Duration(seconds: 1),
}) {
  return RealtimeSession(
    socketClient: socket,
    taskId: '2743770',
    taskToken: 'task-token',
    readyTimeout: readyTimeout,
  );
}

final class FakeRealtimeSocketClient implements RealtimeSocketClient {
  final StreamController<Object?> _controller =
      StreamController<Object?>.broadcast(sync: true);

  final List<String> sentText = [];
  final List<Uint8List> sentBinary = [];
  int connectCalls = 0;
  int closeCalls = 0;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    _connected = true;
  }

  @override
  void sendBinary(Uint8List bytes) {
    sentBinary.add(Uint8List.fromList(bytes));
  }

  @override
  void sendText(String message) {
    sentText.add(message);
  }

  @override
  Future<void> close() async {
    if (!_connected) {
      return;
    }
    closeCalls++;
    _connected = false;
  }

  void emit(Object? frame) {
    _controller.add(frame);
  }

  Future<void> finish() async {
    _connected = false;
    await _controller.close();
  }

  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
