import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The ASN.1 `DigestInfo` prefix of a SHA-256 digest (RFC 8017 §9.2).
const List<int> _sha256DigestInfoPrefix = <int>[
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// Minimum number of padding bytes required by PKCS#1 v1.5.
const int _minPaddingLength = 8;

/// Verification of RSASSA-PKCS1-v1_5 signatures.
///
/// The implementation only relies on the Dart SDK and `package:crypto`: the
/// modular exponentiation uses [BigInt.modPow] and the padding is rebuilt
/// exactly as described by RFC 8017 §9.2.
abstract final class RsaVerifier {
  /// Verifies [signature] against [message] with the RSA public key made of
  /// the modulus [modulus] and the exponent [exponent].
  ///
  /// Returns `false` instead of throwing: a malformed signature is an
  /// expected input, not an exceptional situation.
  static bool verify(
    Map<String, dynamic> jwk,
    List<int> message,
    List<int> signature,
  ) {
    final BigInt? modulus = _decodeBigInt(jwk['n']);
    final BigInt? exponent = _decodeBigInt(jwk['e']);
    if (modulus == null || exponent == null) return false;
    if (modulus <= BigInt.zero || exponent <= BigInt.zero) return false;

    final int length = (modulus.bitLength + 7) ~/ 8;
    if (signature.length != length) return false;

    final BigInt signatureValue = _bytesToBigInt(signature);
    if (signatureValue >= modulus) return false;

    final BigInt decrypted = signatureValue.modPow(exponent, modulus);
    final Uint8List encoded = _bigIntToBytes(decrypted, length);

    final Uint8List? expected = _expectedEncodedMessage(message, length);
    if (expected == null) return false;

    return _constantTimeEquals(encoded, expected);
  }

  /// Builds the expected PKCS#1 v1.5 encoded message of [message].
  static Uint8List? _expectedEncodedMessage(List<int> message, int length) {
    final Uint8List digest = Uint8List.fromList(sha256.convert(message).bytes);
    final int payloadLength = _sha256DigestInfoPrefix.length + digest.length;
    if (length < payloadLength + _minPaddingLength + 3) return null;

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
    encoded.setRange(
      paddingEnd + 1 + _sha256DigestInfoPrefix.length,
      length,
      digest,
    );
    return encoded;
  }

  /// Decodes a base64url encoded unsigned big endian integer.
  static BigInt? _decodeBigInt(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      final Uint8List bytes = base64Url.decode(base64Url.normalize(value));
      if (bytes.isEmpty) return null;
      return _bytesToBigInt(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Reads an unsigned big endian byte string as a big integer.
  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final int byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  /// Writes a big integer as a fixed length unsigned big endian byte string.
  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final Uint8List bytes = Uint8List(length);
    var remaining = value;
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return bytes;
  }

  /// Compares two byte strings without leaking their content by timing.
  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
