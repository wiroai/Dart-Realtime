import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

final class WiroHttpResponse {
  const WiroHttpResponse({
    required this.statusCode,
    required this.data,
  });

  final int statusCode;
  final Object? data;
}

abstract interface class WiroHttpClient {
  Future<WiroHttpResponse> post({
    required String path,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    WiroRequestCancellation? cancellation,
  });

  void close();
}
