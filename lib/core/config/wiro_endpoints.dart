/// Official Wiro HTTP and WebSocket bases verified 2026-08-21.
abstract final class WiroEndpoints {
  static const String restBaseUrl = 'https://api.wiro.ai/v1';
  static const String webSocketUrl = 'wss://socket.wiro.ai/v1';
  static const String taskCancelPath = '/Task/Cancel';
  static const String taskKillPath = '/Task/Kill';

  static String runPath({
    required String owner,
    required String model,
  }) {
    return '/Run/$owner/$model';
  }
}
