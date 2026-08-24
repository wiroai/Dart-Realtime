import 'package:flutter/foundation.dart';

@immutable
final class WiroCredentials {
  const WiroCredentials({
    required this.apiKey,
    this.apiSecret,
  });

  final String apiKey;
  final String? apiSecret;

  bool get usesSignature {
    final secret = apiSecret;
    return secret != null && secret.isNotEmpty;
  }
}
