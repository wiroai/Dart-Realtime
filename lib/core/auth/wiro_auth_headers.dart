import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/auth/wiro_nonce_generator.dart';
import 'package:wiro_realtime/core/auth/wiro_request_signer.dart';

final class WiroAuthHeaders {
  WiroAuthHeaders({
    required this.credentials,
    WiroNonceGenerator? nonceGenerator,
    WiroRequestSigner? signer,
  }) : _nonceGenerator = nonceGenerator ?? MonotonicWiroNonceGenerator().call,
       _signer = signer ?? createWiroRequestSignature;

  static const String apiKeyHeader = 'x-api-key';
  static const String nonceHeader = 'x-nonce';
  static const String signatureHeader = 'x-signature';

  final WiroCredentials credentials;
  final WiroNonceGenerator _nonceGenerator;
  final WiroRequestSigner _signer;

  Map<String, String> create() {
    final headers = <String, String>{
      apiKeyHeader: credentials.apiKey,
    };
    final apiSecret = credentials.apiSecret;
    if (apiSecret == null || apiSecret.isEmpty) {
      return headers;
    }

    final nonce = _nonceGenerator();
    headers
      ..[nonceHeader] = nonce
      ..[signatureHeader] = _signer(
        apiKey: credentials.apiKey,
        apiSecret: apiSecret,
        nonce: nonce,
      );
    return headers;
  }
}
