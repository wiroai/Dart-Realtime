import 'package:wiro_realtime/core/auth/wiro_credentials.dart';

abstract final class WiroEnvironment {
  static const String apiKeyName = 'WIRO_API_KEY';
  static const String apiSecretName = 'WIRO_API_SECRET';

  static WiroCredentials fromDartDefines() {
    return fromValues(
      apiKey: const String.fromEnvironment(apiKeyName),
      apiSecret: const String.fromEnvironment(apiSecretName),
    );
  }

  static WiroCredentials fromValues({
    required String apiKey,
    String? apiSecret,
  }) {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      throw StateError(
        'Missing required --dart-define=$apiKeyName=<value>.',
      );
    }

    final normalizedApiSecret = apiSecret?.trim() ?? '';
    return WiroCredentials(
      apiKey: normalizedApiKey,
      apiSecret: normalizedApiSecret.isEmpty ? null : normalizedApiSecret,
    );
  }
}
