import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/realtime_binary_frame.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';
import 'package:wiro_realtime/core/realtime/realtime_event_parser.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_metrics.dart';
import 'package:wiro_realtime/core/realtime/realtime_socket_client.dart';

typedef RealtimeSessionFactory = RealtimeSessionClient Function({
  required String taskId,
  required String taskToken,
});

abstract interface class RealtimeSessionClient {
  Stream<RealtimeEvent> get events;

  bool get isReady;

  bool get isClosed;

  RealtimeSessionMetrics get metrics;

  Future<void> connect();

  bool sendAudio(Uint8List pcmBytes);

  void sendSessionEnd();

  Future<void> stop();

  Future<void> close();
}

final class RealtimeSession implements RealtimeSessionClient {
  factory RealtimeSession({
    required RealtimeSocketClient socketClient,
    required String taskId,
    required String taskToken,
    RealtimeEventParser parser = const RealtimeEventParser(),
    Duration readyTimeout = const Duration(seconds: 15),
    Duration closeTimeout = const Duration(seconds: 3),
  }) {
    return RealtimeSession._(
      socketClient,
      taskId,
      taskToken,
      parser,
      readyTimeout,
      closeTimeout,
    );
  }

  RealtimeSession._(
    this._socketClient,
    this._taskId,
    this._taskToken,
    this._parser,
    this._readyTimeout,
    this._closeTimeout,
  );

  final RealtimeSocketClient _socketClient;
  final String _taskId;
  final String _taskToken;
  final RealtimeEventParser _parser;
  final Duration _readyTimeout;
  final Duration _closeTimeout;
  final StreamController<RealtimeEvent> _eventsController =
      StreamController<RealtimeEvent>.broadcast(sync: true);
  final Completer<void> _readyCompleter = Completer<void>();
  final RealtimeSessionMetricsCollector _metricsCollector =
      RealtimeSessionMetricsCollector();

  /// Reused across frames; fifty audio frames a second would otherwise
  /// allocate fifty throwaway stopwatches.
  final Stopwatch _parseStopwatch = Stopwatch();

  StreamSubscription<Object?>? _socketSubscription;
  Future<void>? _connectFuture;
  Future<void>? _closeFuture;
  bool _ready = false;
  bool _closed = false;
  bool _subscriptionSent = false;
  bool _sessionEndSent = false;

  @override
  Stream<RealtimeEvent> get events => _eventsController.stream;

  @override
  bool get isReady => _ready && !_closed;

  @override
  bool get isClosed => _closed;

  @override
  RealtimeSessionMetrics get metrics => _metricsCollector.snapshot;

  @override
  Future<void> connect() {
    return _connectFuture ??= _connect();
  }

  @override
  bool sendAudio(Uint8List pcmBytes) {
    if (!isReady || pcmBytes.isEmpty) {
      return false;
    }
    _socketClient.sendBinary(
      RealtimeBinaryFrame.encode(
        taskToken: _taskToken,
        payload: pcmBytes,
      ),
    );
    return true;
  }

  @override
  void sendSessionEnd() {
    if (_closed || !_socketClient.isConnected || _sessionEndSent) {
      return;
    }
    _sessionEndSent = true;
    final payload = jsonEncode({
      'type': 'task_session_end',
      'tasktoken': _taskToken,
    });
    _socketClient.sendText(payload);
  }

  @override
  Future<void> stop() async {
    sendSessionEnd();
    await close();
  }

  @override
  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _connect() async {
    if (_closed) {
      throw const WiroCancellationFailure();
    }

    await _socketClient.connect();
    if (_closed) {
      await _socketClient.close();
      throw const WiroCancellationFailure();
    }

    _socketSubscription = _socketClient.messages.listen(
      _handleFrame,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
    );
    _sendSubscription();

    try {
      await _readyCompleter.future.timeout(_readyTimeout);
    } on TimeoutException {
      await close();
      throw const WiroReadyTimeoutFailure();
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _ready = false;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(const WiroCancellationFailure());
    }
    try {
      await _socketSubscription?.cancel().timeout(_closeTimeout);
    } on TimeoutException {
      // Cleanup continues so local state never remains blocked.
    }
    try {
      await _socketClient.close().timeout(_closeTimeout);
    } on TimeoutException {
      // The platform transport may still finish closing in the background.
    }
    await _eventsController.close();
  }

  void _sendSubscription() {
    if (_subscriptionSent) {
      return;
    }
    _subscriptionSent = true;
    final payload = jsonEncode({
      'type': 'task_info',
      'tasktoken': _taskToken,
    });
    _socketClient.sendText(payload);
  }

  void _handleFrame(Object? frame) {
    if (_closed) {
      return;
    }
    _parseStopwatch
      ..reset()
      ..start();
    final event = _normalizeEvent(_parser.parse(frame));
    _parseStopwatch.stop();
    _metricsCollector.record(event, _parseStopwatch.elapsedMicroseconds);
    _eventsController.add(event);

    switch (event) {
      case RealtimeStatusEvent(
        type: RealtimeEventType.streamReady,
      ):
        _ready = true;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      case RealtimeStatusEvent(
        type: RealtimeEventType.postprocessEnded,
      ):
        unawaited(close());
      case RealtimeCancelEvent():
        _fail(const WiroCancellationFailure());
      case RealtimeMalformedEvent():
        _fail(const WiroProtocolFailure());
      // A live task_error frame is the model's stderr — an interim log,
      // not a verdict. Wiro's docs are explicit that the task may still
      // succeed; a genuinely dead task shows itself by closing the
      // socket, which the done handler already turns into a failure.
      case RealtimeErrorEvent():
      case RealtimeStatusEvent():
      case RealtimeOutputEvent():
      case RealtimeBinaryEvent():
      case RealtimeUnknownEvent():
        break;
    }
  }

  void _handleSocketError(Object _) {
    if (_closed) {
      return;
    }
    if (kDebugMode) {
      debugPrint('Realtime socket stream emitted an error.');
    }
    const failure = WiroSocketFailure();
    _eventsController.addError(failure);
    _fail(failure);
  }

  RealtimeEvent _normalizeEvent(RealtimeEvent event) {
    if (event is! RealtimeBinaryEvent) {
      return event;
    }
    final tokenPayload = RealtimeBinaryFrame.decodePayload(
      taskToken: _taskToken,
      frame: event.bytes,
    );
    final payload =
        tokenPayload ??
        RealtimeBinaryFrame.decodePayload(
          taskToken: _taskId,
          frame: event.bytes,
        );
    if (payload == null) {
      if (kDebugMode) {
        debugPrint(
          'Malformed realtime binary frame: '
          'length=${event.bytes.length} '
          'separatorIndex=${event.bytes.indexOf(0x7C)} '
          'expectedTokenPrefixLength='
          '${utf8.encode(_taskToken).length + 1} '
          'expectedTaskIdPrefixLength='
          '${utf8.encode(_taskId).length + 1}',
        );
      }
      return const RealtimeMalformedEvent();
    }
    return RealtimeBinaryEvent(payload);
  }

  void _handleSocketDone() {
    if (_closed) {
      return;
    }
    if (kDebugMode) {
      debugPrint('Realtime socket stream closed remotely.');
    }
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(const WiroSocketFailure());
    }
    unawaited(close());
  }

  void _fail(WiroFailure failure) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(failure);
    }
    unawaited(close());
  }
}
