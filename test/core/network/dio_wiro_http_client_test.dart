import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

void main() {
  test('maps Dio timeout errors to WiroTimeoutFailure', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            ),
          );
        },
      ),
    );
    final client = DioWiroHttpClient.withDio(dio);

    await expectLater(
      client.post(
        path: '/Run/owner/model',
        headers: const {},
        body: const {},
      ),
      throwsA(isA<WiroTimeoutFailure>()),
    );
  });

  test('maps request cancellation to WiroCancellationFailure', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final client = DioWiroHttpClient.withDio(dio);
    final cancellation = WiroRequestCancellation()..cancel();

    await expectLater(
      client.post(
        path: '/Run/owner/model',
        headers: const {},
        body: const {},
        cancellation: cancellation,
      ),
      throwsA(isA<WiroCancellationFailure>()),
    );
  });

  test('request cancellation is idempotent', () {
    final cancellation = WiroRequestCancellation()
      ..cancel()
      ..cancel();

    expect(cancellation.isCancelled, isTrue);
  });
}
