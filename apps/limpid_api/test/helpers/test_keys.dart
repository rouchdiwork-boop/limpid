import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A RSA key pair generated for the tests.
///
/// The pair is produced with the Dart SDK only: two probable primes are
/// drawn, the modulus and the private exponent are derived from them, and
/// the signatures are built following PKCS#1 v1.5 (RFC 8017 §9.2). The
/// verification path of the API is therefore exercised with real
/// cryptography, not with a stub.
final class TestRsaKeyPair {
  /// Creates a key pair.
  const TestRsaKeyPair({
    required this.modulus,
    required this.exponent,
    required this.privateExponent,
    required this.sizeInBytes,
  });

  /// The modulus of the public key.
  final BigInt modulus;

  /// The public exponent.
  final BigInt exponent;

  /// The private exponent.
  final BigInt privateExponent;

  /// The length of the modulus, in bytes.
  final int sizeInBytes;

  /// Signs [message] with the private key.
  Uint8List sign(List<int> message) {
    final Uint8List encoded = _encode(message, sizeInBytes);
    final BigInt signature = _toBigInt(
      encoded,
    ).modPow(privateExponent, modulus);
    return _toBytes(signature, sizeInBytes);
  }

  /// The public JWK of the pair.
  Map<String, dynamic> toJwk(String kid) {
    return <String, dynamic>{
      'kty': 'RSA',
      'kid': kid,
      'alg': 'RS256',
      'use': 'sig',
      'n': _base64Url(_toBytes(modulus, sizeInBytes)),
      'e': _base64Url(_toBytes(exponent, 3)),
    };
  }
}

/// Generates a RSA key pair for the tests.
TestRsaKeyPair generateTestKeyPair({int bits = 2048, int seed = 20261025}) {
  final Random random = Random(seed);
  final BigInt exponent = BigInt.from(65537);
  while (true) {
    final BigInt p = _randomPrime(random, bits ~/ 2);
    final BigInt q = _randomPrime(random, bits ~/ 2);
    if (p == q) continue;
    final BigInt modulus = p * q;
    if (modulus.bitLength != bits) continue;
    final BigInt phi = (p - BigInt.one) * (q - BigInt.one);
    final BigInt gcd = phi.gcd(exponent);
    if (gcd != BigInt.one) continue;
    final BigInt privateExponent = exponent.modInverse(phi);
    return TestRsaKeyPair(
      modulus: modulus,
      exponent: exponent,
      privateExponent: privateExponent,
      sizeInBytes: bits ~/ 8,
    );
  }
}

/// Signs the tokens of the tests with a RSA key pair.
final class TestTokenIssuer {
  /// Creates an issuer.
  const TestTokenIssuer(this.keyPair, {this.kid = 'test-key'});

  /// The key pair signing the tokens.
  final TestRsaKeyPair keyPair;

  /// The identifier of the key.
  final String kid;

  /// Issues a signed token.
  String issue({
    required String userId,
    String? email,
    DateTime? expiresAt,
    DateTime? notBefore,
    String? issuer,
    String? audience,
    String? subject,
    String? role,
  }) {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, dynamic> header = <String, dynamic>{
      'alg': 'RS256',
      'typ': 'JWT',
      'kid': kid,
    };
    final Map<String, dynamic> payload = <String, dynamic>{
      'sub': subject ?? userId,
      'email': email ?? '$userId@example.test',
      'iss': issuer ?? 'https://project.test/auth/v1',
      'aud': audience ?? 'authenticated',
      'role': role ?? 'authenticated',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp':
          (expiresAt ?? now.add(const Duration(hours: 1)))
              .millisecondsSinceEpoch ~/
          1000,
      if (notBefore != null) 'nbf': notBefore.millisecondsSinceEpoch ~/ 1000,
    };

    final String encodedHeader = _base64Url(utf8.encode(jsonEncode(header)));
    final String encodedPayload = _base64Url(utf8.encode(jsonEncode(payload)));
    final String signingInput = '$encodedHeader.$encodedPayload';
    final Uint8List signature = keyPair.sign(utf8.encode(signingInput));
    return '$signingInput.${_base64Url(signature)}';
  }
}

final List<int> _sha256DigestInfoPrefix = <int>[
  0x30,
  0x31,
  0x30,
  0x0d,
  0x06,
  0x09,
  0x60,
  0x86,
  0x48,
  0x01,
  0x65,
  0x03,
  0x04,
  0x02,
  0x01,
  0x05,
  0x00,
  0x04,
  0x20,
];

Uint8List _encode(List<int> message, int length) {
  final Uint8List digest = Uint8List.fromList(sha256.convert(message).bytes);
  final int payloadLength = _sha256DigestInfoPrefix.length + digest.length;
  final Uint8List encoded = Uint8List(length);
  encoded[0] = 0x00;
  encoded[1] = 0x01;
  final int paddingEnd = length - payloadLength - 1;
  for (var i = 2; i < paddingEnd; i++) {
    encoded[i] = 0xff;
  }
  encoded[paddingEnd] = 0x00;
  encoded.setRange(
    paddingEnd + 1,
    paddingEnd + 1 + _sha256DigestInfoPrefix.length,
    _sha256DigestInfoPrefix,
  );
  encoded.setRange(length - digest.length, length, digest);
  return encoded;
}

BigInt _toBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _toBytes(BigInt value, int length) {
  final Uint8List bytes = Uint8List(length);
  var remaining = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}

String _base64Url(List<int> bytes) => base64Url.encode(bytes);

BigInt _randomPrime(Random random, int bits) {
  while (true) {
    final BigInt candidate = _randomOdd(random, bits);
    if (_isProbablePrime(candidate, random)) return candidate;
  }
}

BigInt _randomOdd(Random random, int bits) {
  final List<int> bytes = List<int>.generate(
    (bits + 7) ~/ 8,
    (int _) => random.nextInt(256),
  );
  var value = BigInt.zero;
  for (final int byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  final int shift = value.bitLength - bits;
  value = value >> (shift < 0 ? 0 : shift);
  value = value | BigInt.one;
  value = value | (BigInt.one << (bits - 1));
  return value;
}

bool _isProbablePrime(BigInt candidate, Random random) {
  if (candidate < BigInt.two) return false;
  for (final int small in const <int>[
    2,
    3,
    5,
    7,
    11,
    13,
    17,
    19,
    23,
    29,
    31,
    37,
  ]) {
    final BigInt value = BigInt.from(small);
    if (candidate == value) return true;
    if (candidate % value == BigInt.zero) return false;
  }

  final BigInt minusOne = candidate - BigInt.one;
  var d = minusOne;
  var r = 0;
  while (d.isEven) {
    d = d >> 1;
    r += 1;
  }

  for (int round = 0; round < 12; round++) {
    final BigInt a = BigInt.from(random.nextInt(1 << 30) + 2);
    if (a >= candidate) continue;
    BigInt x = a.modPow(d, candidate);
    if (x == BigInt.one || x == minusOne) continue;
    var witness = true;
    for (var i = 1; i < r; i++) {
      x = x.modPow(BigInt.two, candidate);
      if (x == minusOne) {
        witness = false;
        break;
      }
    }
    if (witness) return false;
  }
  return true;
}
