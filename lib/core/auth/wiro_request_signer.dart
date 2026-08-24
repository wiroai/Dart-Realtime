import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef WiroRequestSigner = String Function({
  required String apiKey,
  required String apiSecret,
  required String nonce,
});

String createWiroRequestSignature({
  required String apiKey,
  required String apiSecret,
  required String nonce,
}) {
  final hmac = Hmac(sha256, utf8.encode(apiKey));
  return hmac.convert(utf8.encode('$apiSecret$nonce')).toString();
}
