import 'dart:convert';
import 'dart:typed_data';

abstract final class RealtimeBinaryFrame {
  static const int _separator = 0x7C;

  static Uint8List encode({
    required String taskToken,
    required Uint8List payload,
  }) {
    final tokenBytes = utf8.encode(taskToken);
    return Uint8List(tokenBytes.length + 1 + payload.length)
      ..setAll(0, tokenBytes)
      ..[tokenBytes.length] = _separator
      ..setAll(tokenBytes.length + 1, payload);
  }

  static Uint8List? decodePayload({
    required String taskToken,
    required Uint8List frame,
  }) {
    final tokenBytes = utf8.encode(taskToken);
    final payloadOffset = tokenBytes.length + 1;
    if (frame.length < payloadOffset ||
        frame[tokenBytes.length] != _separator) {
      return null;
    }
    for (var index = 0; index < tokenBytes.length; index++) {
      if (frame[index] != tokenBytes[index]) {
        return null;
      }
    }
    return Uint8List.fromList(
      Uint8List.sublistView(frame, payloadOffset),
    );
  }
}
