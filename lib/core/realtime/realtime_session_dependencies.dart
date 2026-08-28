import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/web_socket_realtime_socket_client.dart';

/// The Wiro stack every realtime feature stands up the same way.
///
/// One HTTP client, the signed API client on top of it, and a session
/// factory whose ready-wait outlives the model's cold start. Features
/// differ only in that wait — the socket replays nothing to a subscriber
/// that arrives after an event fired, so the ready timeout is sized per
/// model rather than shared.
///
/// Owns the HTTP client it creates; [close] releases it.
final class RealtimeSessionDependencies {
  factory RealtimeSessionDependencies({
    required WiroCredentials credentials,
    required Duration readyTimeout,
  }) {
    final httpClient = DioWiroHttpClient();
    return RealtimeSessionDependencies._(
      httpClient,
      DefaultWiroApiClient(
        httpClient,
        WiroAuthHeaders(credentials: credentials),
      ),
      readyTimeout,
    );
  }

  RealtimeSessionDependencies._(
    this._httpClient,
    this.apiClient,
    this._readyTimeout,
  );

  final WiroHttpClient _httpClient;
  final WiroApiClient apiClient;
  final Duration _readyTimeout;

  /// Matches [RealtimeSessionFactory], so it can be passed as one.
  RealtimeSession createSession({
    required String taskId,
    required String taskToken,
  }) {
    return RealtimeSession(
      socketClient: WebSocketRealtimeSocketClient(),
      taskId: taskId,
      taskToken: taskToken,
      readyTimeout: _readyTimeout,
    );
  }

  void close() => _httpClient.close();
}
