import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';

/// Translates session errors into a user-facing message and a stable
/// machine-readable code.
///
/// Errors outside the project's sealed failure hierarchies collapse to
/// [fallbackMessage] and the `unknown` code, so raw exception text never
/// reaches the UI or the protocol log.
final class RealtimeFailureMapper {
  const RealtimeFailureMapper({required this.fallbackMessage});

  static const String unknownCode = 'unknown';

  final String fallbackMessage;

  String messageFor(Object error) {
    return switch (error) {
      WiroFailure() => error.message,
      AudioFailure() => error.message,
      _ => fallbackMessage,
    };
  }

  String codeFor(Object error) {
    return switch (error) {
      WiroFailure() => error.code.name,
      AudioFailure() => error.code.name,
      _ => unknownCode,
    };
  }
}
