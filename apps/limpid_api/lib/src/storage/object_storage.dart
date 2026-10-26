import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sig_v4.dart';

/// The storage of the binary artefacts of the platform.
///
/// The API stores the exported books and the generated covers in Cloudflare
/// R2, which speaks the S3 dialect.
abstract interface class ObjectStorage {
  /// Stores [bytes] under [key].
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  });

  /// Builds a temporary download URL for [key].
  Future<String> presignedUrl({required String key, required Duration expires});
}

/// An [ObjectStorage] backed by Cloudflare R2.
///
/// The requests are signed with AWS Signature Version 4, the dialect R2
/// understands.
final class R2ObjectStorage implements ObjectStorage {
  /// Creates a storage.
  R2ObjectStorage({
    required this.endpoint,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.region = 'auto',
    this.service = 's3',
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  /// The S3 compatible endpoint of the account.
  final String endpoint;

  /// The bucket holding the artefacts.
  final String bucket;

  /// The access key identifier.
  final String accessKeyId;

  /// The secret access key.
  final String secretAccessKey;

  /// The signing region; Cloudflare R2 uses `auto`.
  final String region;

  /// The signing service.
  final String service;

  /// The time budget of a call to R2.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final Uri uri = _objectUri(key);
    final Map<String, String> headers = <String, String>{
      'host': uri.authority,
      'content-type': contentType,
      'x-amz-content-sha256': SigV4.hexSha256(bytes),
    };
    final Map<String, String> signed = SigV4.sign(
      method: 'PUT',
      uri: uri,
      headers: headers,
      payload: bytes,
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      region: region,
      service: service,
      timestamp: DateTime.now().toUtc(),
    );

    final http.Response response = await _client
        .put(uri, headers: signed, body: bytes)
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'R2 refused the object "$key" (${response.statusCode}).',
      );
    }
  }

  @override
  Future<String> presignedUrl({
    required String key,
    required Duration expires,
  }) async {
    final Uri uri = _objectUri(key);
    final Map<String, String> query = SigV4.presignQuery(
      uri: uri,
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      region: region,
      service: service,
      timestamp: DateTime.now().toUtc(),
      expires: expires,
    );
    return uri.replace(queryParameters: query).toString();
  }

  Uri _objectUri(String key) {
    final String base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    return Uri.parse('$base/$bucket/${_encodePath(key)}');
  }

  static String _encodePath(String key) {
    return key.split('/').map(_encode).join('/');
  }

  static String _encode(String value) {
    const String unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final StringBuffer buffer = StringBuffer();
    for (final int code in utf8.encode(value)) {
      final String character = String.fromCharCode(code);
      if (unreserved.contains(character)) {
        buffer.write(character);
        continue;
      }
      buffer.write('%');
      buffer.write(code.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// An in-memory [ObjectStorage], used by the test suite.
final class InMemoryObjectStorage implements ObjectStorage {
  /// Creates an empty storage.
  InMemoryObjectStorage();

  final Map<String, Uint8List> _objects = <String, Uint8List>{};

  /// The keys currently stored, for the assertions of the test suite.
  List<String> get keys => List<String>.unmodifiable(_objects.keys);

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    _objects[key] = bytes;
  }

  @override
  Future<String> presignedUrl({
    required String key,
    required Duration expires,
  }) async {
    return 'https://storage.test/$key?expires=${expires.inSeconds}';
  }
}
