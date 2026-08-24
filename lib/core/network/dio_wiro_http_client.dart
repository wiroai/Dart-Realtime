import 'dart:async';

import 'package:dio/dio.dart';
import 'package:wiro_realtime/core/config/wiro_endpoints.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

final class DioWiroHttpClient implements WiroHttpClient {
  DioWiroHttpClient({
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: WiroEndpoints.restBaseUrl,
           connectTimeout: connectTimeout,
           sendTimeout: sendTimeout,
           receiveTimeout: receiveTimeout,
           contentType: Headers.jsonContentType,
           validateStatus: (_) => true,
         ),
       );

  DioWiroHttpClient.withDio(Dio dio) : _dio = dio;

  final Dio _dio;

  @override
  void close() {
    _dio.close(force: true);
  }

  @override
  Future<WiroHttpResponse> post({
    required String path,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    WiroRequestCancellation? cancellation,
  }) async {
    final cancelToken = CancelToken();
    if (cancellation?.isCancelled ?? false) {
      cancelToken.cancel();
    } else if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) => cancelToken.cancel()),
      );
    }

    try {
      final response = await _dio.post<Object?>(
        path,
        data: body,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      final statusCode = response.statusCode;
      if (statusCode == null) {
        throw const WiroMalformedResponseFailure();
      }
      return WiroHttpResponse(
        statusCode: statusCode,
        data: response.data,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  WiroFailure _mapDioException(DioException error) {
    return switch (error.type) {
      DioExceptionType.cancel => const WiroCancellationFailure(),
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => const WiroTimeoutFailure(),
      DioExceptionType.badResponse => _mapStatusCode(
        error.response?.statusCode,
      ),
      DioExceptionType.badCertificate ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => const WiroNetworkFailure(),
    };
  }

  WiroFailure _mapStatusCode(int? statusCode) {
    return switch (statusCode) {
      401 || 403 => const WiroAuthenticationFailure(),
      429 => const WiroRateLimitFailure(),
      _ => const WiroServerFailure(),
    };
  }
}
