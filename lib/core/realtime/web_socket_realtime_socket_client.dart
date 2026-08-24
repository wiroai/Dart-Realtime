import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wiro_realtime/core/config/wiro_endpoints.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/realtime_socket_client.dart';

final class WebSocketRealtimeSocketClient implements RealtimeSocketClient {
  WebSocketRealtimeSocketClient({
    Uri? endpoint,
    this.connectTimeout = const Duration(seconds: 10),
  }) : _endpoint = endpoint ?? Uri.parse(WiroEndpoints.webSocketUrl);

  final Uri _endpoint;
  final Duration connectTimeout;
  final StreamController<Object?> _messagesController =
      StreamController<Object?>.broadcast(sync: true);

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  bool _connected = false;
  bool _closed = false;
  bool _messagesClosed = false;

  @override
  bool get isConnected => _connected && !_closed;

  @override
  Stream<Object?> get messages => _messagesController.stream;

  @override
  Future<void> connect() async {
    if (isConnected) {
      return;
    }
    if (_closed) {
      throw const WiroSocketFailure();
    }

    try {
      final channel = WebSocketChannel.connect(_endpoint);
      _channel = channel;
      await channel.ready.timeout(connectTimeout);
      _connected = true;
      _subscription = channel.stream.listen(
        _messagesController.add,
        onError: (_) {
          _messagesController.addError(const WiroSocketFailure());
        },
        onDone: () {
          _connected = false;
          unawaited(_closeMessages());
        },
      );
    } on TimeoutException {
      await _channel?.sink.close();
      _channel = null;
      throw const WiroSocketConnectTimeoutFailure();
    } on Object {
      await _channel?.sink.close();
      _channel = null;
      throw const WiroSocketFailure();
    }
  }

  @override
  void sendText(String message) {
    _send(message);
  }

  @override
  void sendBinary(Uint8List bytes) {
    _send(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _connected = false;
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _closeMessages();
  }

  void _send(Object message) {
    if (!isConnected) {
      throw const WiroSocketFailure();
    }
    _channel!.sink.add(message);
  }

  Future<void> _closeMessages() async {
    if (_messagesClosed) {
      return;
    }
    _messagesClosed = true;
    await _messagesController.close();
  }
}
