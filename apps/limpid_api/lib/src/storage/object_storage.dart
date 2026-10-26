import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'r2_listing.dart';
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

/// The erasure of the objects of a storage.
///
/// The port is a sibling of [ObjectStorage] and not a part of it : the
/// storages standing for an absent remote service only know how to refuse a
/// call, and adding the erasure to [ObjectStorage] would force every one of
/// them to implement it.
///
/// Les implémentations qui savent effacer sont [R2ObjectStorage] et
/// [InMemoryObjectStorage].
abstract interface class ObjectStorageDeletion {
  /// Erases the object [key].
  ///
  /// The call is idempotent: erasing an object that is already gone is not
  /// an error.
  Future<void> delete({required String key});

  /// Erases every object whose key starts with [prefix].
  ///
  /// The method answers the number of erased objects.
  Future<int> deletePrefix({required String prefix});
}

/// An [ObjectStorage] backed by Cloudflare R2.
///
/// The requests are signed with AWS Signature Version 4, the dialect R2
/// understands.
final class R2ObjectStorage implements ObjectStorage, ObjectStorageDeletion {
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

  /// The number of objects read by a listing.
  static const int listingPageSize = 1000;

  /// The number of pages a single erasure may read.
  ///
  /// The bound keeps a bucket that never ends from holding the worker
  /// forever : a prefix holding that many pages is a defect, and the purge
  /// must say so rather than spin.
  static const int listingPageLimit = 1000;

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

  @override
  Future<void> delete({required String key}) async {
    await _eraseKey(key);
  }

  @override
  Future<int> deletePrefix({required String prefix}) async {
    int erased = 0;
    String? token;
    int pages = 0;
    do {
      final R2ObjectListing listing = await _listObjects(
        prefix: prefix,
        continuationToken: token,
      );
      for (final String key in listing.keys) {
        await _eraseKey(key);
        erased++;
      }
      if (listing.isTruncated && listing.continuationToken == null) {
        throw StateError(
          'R2 truncated the listing of "$prefix" without giving a token.',
        );
      }
      token = listing.isTruncated ? listing.continuationToken : null;
      pages++;
      if (pages > listingPageLimit) {
        throw StateError(
          'R2 returned too many pages of objects for the prefix "$prefix".',
        );
      }
    } while (token != null);
    return erased;
  }

  /// Reads a page of the objects whose key starts with [prefix].
  Future<R2ObjectListing> _listObjects({
    required String prefix,
    String? continuationToken,
  }) async {
    final Map<String, String> parameters = <String, String>{
      'list-type': '2',
      'max-keys': '$listingPageSize',
      'prefix': prefix,
    };
    if (continuationToken != null) {
      parameters['continuation-token'] = continuationToken;
    }
    final Uri uri = _bucketUri(parameters);
    final Map<String, String> headers = <String, String>{
      'host': uri.authority,
      'x-amz-content-sha256': SigV4.hexSha256(const <int>[]),
    };
    final Map<String, String> signed = SigV4.sign(
      method: 'GET',
      uri: uri,
      headers: headers,
      payload: Uint8List(0),
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      region: region,
      service: service,
      timestamp: DateTime.now().toUtc(),
    );

    final http.Response response = await _client
        .get(uri, headers: signed)
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'R2 refused to list the objects of the prefix "$prefix" '
        '(${response.statusCode}).',
      );
    }
    return R2ObjectListing.parse(response.body);
  }

  /// Erases one object of the bucket.
  Future<void> _eraseKey(String key) async {
    final Uri uri = _objectUri(key);
    final Map<String, String> headers = <String, String>{
      'host': uri.authority,
      'x-amz-content-sha256': SigV4.hexSha256(const <int>[]),
    };
    final Map<String, String> signed = SigV4.sign(
      method: 'DELETE',
      uri: uri,
      headers: headers,
      payload: Uint8List(0),
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      region: region,
      service: service,
      timestamp: DateTime.now().toUtc(),
    );

    final http.Response response = await _client
        .delete(uri, headers: signed)
        .timeout(timeout);
    if (response.statusCode != HttpStatus.noContent &&
        response.statusCode != HttpStatus.ok) {
      throw StateError(
        'R2 refused to erase the object "$key" (${response.statusCode}).',
      );
    }
  }

  /// The URL of the bucket, carrying the query of a listing.
  ///
  /// The query is written in its canonical form : the names are sorted and
  /// the values are encoded, exactly as the signature expects them.
  Uri _bucketUri(Map<String, String> parameters) {
    final String base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final List<String> names = parameters.keys.toList(growable: false)..sort();
    final String query = names
        .map((String name) => '${_encode(name)}=${_encode(parameters[name]!)}')
        .join('&');
    return Uri.parse('$base/$bucket?$query');
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
final class InMemoryObjectStorage
    implements ObjectStorage, ObjectStorageDeletion {
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

  @override
  Future<void> delete({required String key}) async {
    _objects.remove(key);
  }

  @override
  Future<int> deletePrefix({required String prefix}) async {
    final List<String> keys = _objects.keys
        .where((String key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final String key in keys) {
      _objects.remove(key);
    }
    return keys.length;
  }
}
