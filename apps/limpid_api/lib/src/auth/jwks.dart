import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';

/// A JSON Web Key of the Supabase project.
final class JsonWebKey {
  /// Creates a key.
  const JsonWebKey({
    required this.kid,
    required this.kty,
    required this.alg,
    required this.raw,
  });

  /// Decodes a JWK, returning `null` when it is not an RSA signing key.
  static JsonWebKey? fromJson(Map<String, dynamic> json) {
    final Object? kid = json['kid'];
    final Object? kty = json['kty'];
    final Object? alg = json['alg'];
    if (kid is! String || kid.isEmpty) return null;
    if (kty is! String || kty != 'RSA') return null;
    if (alg is! String || alg != 'RS256') return null;
    if (json['n'] is! String || json['e'] is! String) return null;
    return JsonWebKey(
      kid: kid,
      kty: kty,
      alg: alg,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  /// The identifier of the key, used to select it for a token.
  final String kid;

  /// The type of the key, always `RSA`.
  final String kty;

  /// The algorithm of the key, always `RS256`.
  final String alg;

  /// The raw JWK.
  final Map<String, dynamic> raw;
}

/// A source of JSON Web Keys.
abstract interface class JwksProvider {
  /// Returns the keys, using the cache when it is still fresh.
  Future<Map<String, JsonWebKey>> keys();

  /// Forces a refresh of the keys and returns them.
  Future<Map<String, JsonWebKey>> refresh();
}

/// A [JwksProvider] fetching the key set over HTTP and caching it in memory.
///
/// The cache expires after [ttl]; a token signed with an unknown key id
/// triggers a refresh so a key rotation is picked up immediately.
final class HttpJwksProvider implements JwksProvider {
  /// Creates a provider.
  HttpJwksProvider({
    required this.url,
    required this.ttl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// The URL of the key set.
  final String url;

  /// How long the keys stay cached.
  final Duration ttl;

  /// The time budget of a key set request.
  final Duration timeout;

  final http.Client _client;

  Map<String, JsonWebKey>? _cached;
  DateTime? _cachedAt;
  Future<Map<String, JsonWebKey>>? _inFlight;

  @override
  Future<Map<String, JsonWebKey>> keys() async {
    final Map<String, JsonWebKey>? cached = _cached;
    final DateTime? cachedAt = _cachedAt;
    if (cached != null && cachedAt != null) {
      if (DateTime.now().toUtc().difference(cachedAt) < ttl) {
        return cached;
      }
    }
    return refresh();
  }

  @override
  Future<Map<String, JsonWebKey>> refresh() {
    final Future<Map<String, JsonWebKey>>? pending = _inFlight;
    if (pending != null) return pending;
    final Future<Map<String, JsonWebKey>> future = _fetch();
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<Map<String, JsonWebKey>> _fetch() async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(timeout);
    } on Object catch (error) {
      throw InternalException(
        message: 'Le service d\'authentification est injoignable.',
        details: <String, Object?>{'reason': error.runtimeType.toString()},
        cause: error,
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw InternalException(
        message: 'Le service d\'authentification est injoignable.',
        details: <String, Object?>{'status': response.statusCode},
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw InternalException(
        message:
            'Le service d\'authentification a renvoyé une réponse '
            'invalide.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['keys'] is! List) {
      throw const InternalException(
        message:
            'Le service d\'authentification a renvoyé une réponse '
            'invalide.',
      );
    }

    final Map<String, JsonWebKey> keys = <String, JsonWebKey>{};
    for (final Object? entry in decoded['keys'] as List<dynamic>) {
      if (entry is! Map<String, dynamic>) continue;
      final JsonWebKey? key = JsonWebKey.fromJson(entry);
      if (key != null) keys[key.kid] = key;
    }

    _cached = Map<String, JsonWebKey>.unmodifiable(keys);
    _cachedAt = DateTime.now().toUtc();
    return _cached!;
  }
}
