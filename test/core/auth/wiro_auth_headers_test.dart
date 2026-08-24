import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/auth/wiro_nonce_generator.dart';
import 'package:wiro_realtime/core/auth/wiro_request_signer.dart';

void main() {
  test('creates API-key-only headers', () {
    final headers = WiroAuthHeaders(
      credentials: const WiroCredentials(apiKey: 'test-key'),
    ).create();

    expect(headers, {WiroAuthHeaders.apiKeyHeader: 'test-key'});
  });

  test('creates deterministic signature headers', () {
    final headers = WiroAuthHeaders(
      credentials: const WiroCredentials(
        apiKey: 'test-key',
        apiSecret: 'test-secret',
      ),
      nonceGenerator: () => '1700000000',
    ).create();

    expect(headers[WiroAuthHeaders.apiKeyHeader], 'test-key');
    expect(headers[WiroAuthHeaders.nonceHeader], '1700000000');
    expect(
      headers[WiroAuthHeaders.signatureHeader],
      '0e8b719d1c158c40c2b10415f96c09b794780274f5f9cbaa48d2e723ac07fc3c',
    );
  });

  test('creates a fresh nonce when timestamps are equal', () {
    final generator = MonotonicWiroNonceGenerator(
      microsecondsSinceEpoch: () => 42,
    );

    expect(generator(), '42');
    expect(generator(), '43');
  });

  test('signer emits lowercase hexadecimal output', () {
    final signature = createWiroRequestSignature(
      apiKey: 'test-key',
      apiSecret: 'test-secret',
      nonce: '1700000000',
    );

    expect(signature, signature.toLowerCase());
    expect(signature, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
