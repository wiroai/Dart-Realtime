import 'dart:typed_data';

abstract interface class RealtimeSocketClient {
  Stream<Object?> get messages;

  bool get isConnected;

  Future<void> connect();

  void sendText(String message);

  void sendBinary(Uint8List bytes);

  Future<void> close();
}
