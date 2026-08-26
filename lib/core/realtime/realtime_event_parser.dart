import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';

final class RealtimeEventParser {
  const RealtimeEventParser();

  RealtimeEvent parse(Object? frame) {
    if (frame is Uint8List) {
      return RealtimeBinaryEvent(frame);
    }
    if (frame is List<int>) {
      return RealtimeBinaryEvent(Uint8List.fromList(frame));
    }
    if (frame is! String) {
      _logMalformed(
        'unsupported_frame',
        metadata: {'runtimeType': frame.runtimeType.toString()},
      );
      return const RealtimeMalformedEvent();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      _logMalformed('invalid_json');
      return const RealtimeMalformedEvent();
    }
    if (decoded is! Map<String, dynamic>) {
      _logMalformed(
        'invalid_json_shape',
        metadata: {'runtimeType': decoded.runtimeType.toString()},
      );
      return const RealtimeMalformedEvent();
    }

    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      _logMalformed(
        'missing_type',
        metadata: {'keys': decoded.keys.toList(growable: false)},
      );
      return const RealtimeMalformedEvent();
    }
    if (type == 'task_output') {
      final message = decoded['message'];
      if (message is! String) {
        _logMalformed(
          'invalid_task_output',
          metadata: {'messageType': message.runtimeType.toString()},
        );
      }
      return message is String
          ? RealtimeOutputEvent(message)
          : const RealtimeMalformedEvent();
    }
    if (type == 'task_error' || type == 'task_error_full') {
      _logTaskError(type, decoded);
      return RealtimeErrorEvent(type);
    }
    if (type == 'task_cancel') {
      return const RealtimeCancelEvent();
    }

    final knownType = RealtimeEventType.fromWireName(type);
    return knownType == null
        ? RealtimeUnknownEvent(type)
        : RealtimeStatusEvent(knownType);
  }

  void _logMalformed(
    String reason, {
    Map<String, Object?> metadata = const {},
  }) {
    if (kDebugMode) {
      debugPrint(
        'Malformed realtime frame: reason=$reason metadata=$metadata',
      );
    }
  }

  /// Prints why the server failed the task, so the console answers the
  /// question the session state cannot.
  ///
  /// Debug console only: the payload is never retained on the event, so
  /// raw server text still cannot reach the UI or the protocol log.
  void _logTaskError(String type, Map<String, dynamic> payload) {
    if (!kDebugMode) {
      return;
    }
    final detail = {
      for (final key in const [
        'message',
        'error',
        'detail',
        'description',
        'code',
      ])
        if (payload[key] != null) key: payload[key],
    };
    debugPrint(
      'Realtime $type payload: ${detail.isEmpty ? payload : detail}',
    );
  }
}
