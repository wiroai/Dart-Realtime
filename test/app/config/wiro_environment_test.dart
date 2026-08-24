import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/config/wiro_environment.dart';

void main() {
  test('requires an API key', () {
    expect(
      () => WiroEnvironment.fromValues(apiKey: ' '),
      throwsA(isA<StateError>()),
    );
  });

  test('supports API-key-only projects', () {
    final credentials = WiroEnvironment.fromValues(apiKey: 'api-key');

    expect(credentials.apiKey, 'api-key');
    expect(credentials.apiSecret, isNull);
    expect(credentials.usesSignature, isFalse);
  });

  test('supports signature projects', () {
    final credentials = WiroEnvironment.fromValues(
      apiKey: 'api-key',
      apiSecret: 'api-secret',
    );

    expect(credentials.apiSecret, 'api-secret');
    expect(credentials.usesSignature, isTrue);
  });
}
