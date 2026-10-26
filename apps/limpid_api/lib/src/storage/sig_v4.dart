import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The algorithm of the AWS Signature Version 4.
const String sigV4Algorithm = 'AWS4-HMAC-SHA256';

/// The characters that never need to be percent encoded.
const String _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'abcdefghijklmnopqrstuvwxyz'
    '0123456789'
    '-_.~';

/// The AWS Signature Version 4 signer.
///
/// The signer is implemented here because the S3 SDK published on pub.dev
/// (`aws_s3`, `aws_s3_client`) declares a Dart 2 SDK constraint and cannot be
/// resolved on the Dart 3.12 SDK this API targets. Cloudflare R2 speaks the
/// same SigV4 dialect as S3, with the `auto` region.
abstract final class SigV4 {
  /// Signs a request and returns the headers to add to it.
  ///
  /// [headers] must already carry the `host` header. The `x-amz-date` header
  /// is added when it is missing; the `x-amz-content-sha256` header is signed
  /// only when the caller provides it, as S3 expects it on the requests
  /// carrying a body.
  static Map<String, String> sign({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List payload,
    required String accessKeyId,
    required String secretAccessKey,
    required String region,
    required String service,
    required DateTime timestamp,
    String? sessionToken,
  }) {
    final String amzDate = formatAmzDate(timestamp);
    final String dateStamp = amzDate.substring(0, 8);

    final Map<String, String> signed = <String, String>{
      ...headers,
      'x-amz-date': headers['x-amz-date'] ?? amzDate,
    };
    if (sessionToken != null && sessionToken.isNotEmpty) {
      signed['x-amz-security-token'] = sessionToken;
    }

    final List<String> names =
        signed.keys
            .map((String key) => key.toLowerCase())
            .toList(growable: false)
          ..sort();
    final String canonicalHeaders = names
        .map((String name) => '$name:${_trim(signed[name]!)}\n')
        .join();
    final String signedHeaders = names.join(';');

    final String canonicalRequest = <String>[
      method.toUpperCase(),
      canonicalUriOf(uri),
      canonicalQuery(uri.query),
      canonicalHeaders,
      signedHeaders,
      hexSha256(payload),
    ].join('\n');

    final String scope = '$dateStamp/$region/$service/aws4_request';
    final String stringToSign = <String>[
      sigV4Algorithm,
      amzDate,
      scope,
      hexSha256(utf8.encode(canonicalRequest)),
    ].join('\n');

    final String signature = hex(
      hmacSha256(
        signingKey(
          secretAccessKey: secretAccessKey,
          dateStamp: dateStamp,
          region: region,
          service: service,
        ),
        utf8.encode(stringToSign),
      ),
    );

    return <String, String>{
      ...signed,
      'authorization':
          '$sigV4Algorithm Credential=$accessKeyId/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }

  /// Builds the query parameters of a pre-signed URL.
  ///
  /// The URL grants a temporary read access to one object.
  static Map<String, String> presignQuery({
    required Uri uri,
    required String accessKeyId,
    required String secretAccessKey,
    required String region,
    required String service,
    required DateTime timestamp,
    required Duration expires,
  }) {
    final String amzDate = formatAmzDate(timestamp);
    final String dateStamp = amzDate.substring(0, 8);
    final String scope = '$dateStamp/$region/$service/aws4_request';

    final Map<String, String> query = <String, String>{
      'X-Amz-Algorithm': sigV4Algorithm,
      'X-Amz-Credential': '$accessKeyId/$scope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '${expires.inSeconds}',
      'X-Amz-SignedHeaders': 'host',
    };

    final List<String> queryParts =
        query.entries
            .map(
              (MapEntry<String, String> entry) =>
                  '${_encode(entry.key)}=${_encode(entry.value)}',
            )
            .toList(growable: false)
          ..sort();
    final String canonicalQueryString = queryParts.join('&');

    final String canonicalRequest = <String>[
      'GET',
      canonicalUriOf(uri),
      canonicalQueryString,
      'host:${uri.authority}\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final String stringToSign = <String>[
      sigV4Algorithm,
      amzDate,
      scope,
      hexSha256(utf8.encode(canonicalRequest)),
    ].join('\n');

    final String signature = hex(
      hmacSha256(
        signingKey(
          secretAccessKey: secretAccessKey,
          dateStamp: dateStamp,
          region: region,
          service: service,
        ),
        utf8.encode(stringToSign),
      ),
    );

    return <String, String>{...query, 'X-Amz-Signature': signature};
  }

  /// Formats a timestamp the way the `x-amz-date` header expects it.
  static String formatAmzDate(DateTime timestamp) {
    final DateTime utc = timestamp.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// Computes the hexadecimal SHA-256 digest of [data].
  static String hexSha256(List<int> data) => hex(sha256.convert(data).bytes);

  /// Computes the HMAC-SHA-256 of [data] with [key].
  static List<int> hmacSha256(List<int> key, List<int> data) {
    return Hmac(sha256, key).convert(data).bytes;
  }

  /// Derives the SigV4 signing key.
  static List<int> signingKey({
    required String secretAccessKey,
    required String dateStamp,
    required String region,
    required String service,
  }) {
    final List<int> dateKey = hmacSha256(
      utf8.encode('AWS4$secretAccessKey'),
      utf8.encode(dateStamp),
    );
    final List<int> regionKey = hmacSha256(dateKey, utf8.encode(region));
    final List<int> serviceKey = hmacSha256(regionKey, utf8.encode(service));
    return hmacSha256(serviceKey, utf8.encode('aws4_request'));
  }

  /// Formats bytes as a lowercase hexadecimal string.
  static String hex(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Computes the canonical URI of a request path.
  /// Le chemin canonique d'une requete.
  ///
  /// `Uri.path` rend le chemin **encode** : l'encoder encore encoderait deux
  /// fois les caracteres reserves, et la signature ne correspondrait pas au
  /// document signe. On encode donc les segments **decodes**, une seule fois.
  static String canonicalUriOf(Uri uri) {
    final List<String> segments = uri.pathSegments;
    if (segments.isEmpty) return '/';
    if (segments.length == 1 && segments.first.isEmpty) return '/';
    return '/${segments.map((String segment) => _encode(segment, encodeSlash: false)).join('/')}';
  }

  /// Computes the canonical query string of a request.
  static String canonicalQuery(String query) {
    if (query.isEmpty) return '';
    final List<String> parts = query.split('&').toList(growable: false)..sort();
    return parts.join('&');
  }

  static String _encode(String value, {bool encodeSlash = true}) {
    final StringBuffer buffer = StringBuffer();
    for (final int code in utf8.encode(value)) {
      final String character = String.fromCharCode(code);
      if (_unreserved.contains(character)) {
        buffer.write(character);
        continue;
      }
      if (character == '/' && !encodeSlash) {
        buffer.write(character);
        continue;
      }
      buffer.write('%');
      buffer.write(code.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _trim(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
