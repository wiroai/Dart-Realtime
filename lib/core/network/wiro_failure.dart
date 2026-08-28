enum WiroFailureCode {
  authentication,
  apiRejected,
  rateLimited,
  serverUnavailable,
  networkUnavailable,
  requestTimeout,
  cancelled,
  malformedResponse,
  socketConnection,
  socketConnectTimeout,
  realtimeProtocol,
  streamReadyTimeout,
  sessionBusy,
}

sealed class WiroFailure implements Exception {
  const WiroFailure({
    required this.code,
    required this.message,
    this.diagnostics = const {},
  });

  final WiroFailureCode code;
  final String message;
  final Map<String, String> diagnostics;

  @override
  String toString() => message;
}

final class WiroAuthenticationFailure extends WiroFailure {
  const WiroAuthenticationFailure()
    : super(
        code: WiroFailureCode.authentication,
        message: 'Wiro authentication failed. Check the project credentials.',
      );
}

final class WiroApiFailure extends WiroFailure {
  const WiroApiFailure()
    : super(
        code: WiroFailureCode.apiRejected,
        message: 'Wiro rejected the model Run request.',
      );
}

final class WiroRateLimitFailure extends WiroFailure {
  const WiroRateLimitFailure()
    : super(
        code: WiroFailureCode.rateLimited,
        message: 'Wiro request limit reached. Try again later.',
      );
}

final class WiroServerFailure extends WiroFailure {
  const WiroServerFailure()
    : super(
        code: WiroFailureCode.serverUnavailable,
        message: 'Wiro is temporarily unavailable. Try again later.',
      );
}

final class WiroNetworkFailure extends WiroFailure {
  const WiroNetworkFailure()
    : super(
        code: WiroFailureCode.networkUnavailable,
        message: 'Could not reach Wiro. Check the network connection.',
      );
}

final class WiroTimeoutFailure extends WiroFailure {
  const WiroTimeoutFailure()
    : super(
        code: WiroFailureCode.requestTimeout,
        message: 'The Wiro request timed out. Try again.',
      );
}

final class WiroCancellationFailure extends WiroFailure {
  const WiroCancellationFailure()
    : super(
        code: WiroFailureCode.cancelled,
        message: 'The Wiro request was cancelled.',
      );
}

final class WiroMalformedResponseFailure extends WiroFailure {
  const WiroMalformedResponseFailure()
    : super(
        code: WiroFailureCode.malformedResponse,
        message: 'Wiro returned an unexpected response.',
      );
}

final class WiroSocketFailure extends WiroFailure {
  const WiroSocketFailure()
    : super(
        code: WiroFailureCode.socketConnection,
        message: 'The Wiro realtime connection failed.',
      );
}

final class WiroSocketConnectTimeoutFailure extends WiroFailure {
  const WiroSocketConnectTimeoutFailure()
    : super(
        code: WiroFailureCode.socketConnectTimeout,
        message: 'The Wiro realtime connection timed out. Try again.',
      );
}

final class WiroProtocolFailure extends WiroFailure {
  const WiroProtocolFailure()
    : super(
        code: WiroFailureCode.realtimeProtocol,
        message: 'Wiro returned an unexpected realtime event.',
      );
}

final class WiroReadyTimeoutFailure extends WiroFailure {
  const WiroReadyTimeoutFailure()
    : super(
        code: WiroFailureCode.streamReadyTimeout,
        message: 'The Wiro realtime stream did not become ready in time.',
      );
}

final class WiroSessionBusyFailure extends WiroFailure {
  const WiroSessionBusyFailure()
    : super(
        code: WiroFailureCode.sessionBusy,
        message: 'Another realtime session is already active.',
      );
}
