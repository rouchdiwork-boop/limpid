import 'dart:convert';

import '../errors/app_exception.dart';
import 'auth_context.dart';
import 'jwks.dart';
import 'rsa.dart';

/// Verifies the Supabase JSON Web Tokens presented by the clients.
///
/// The signature is checked against the key set published by the project
/// (JWKS); the registered claims `exp`, `nbf`, `iss` and `aud` are then
/// enforced. A malformed or badly signed token yields an
/// [UnauthorizedException]; a valid but expired token yields a
/// [TokenExpiredException].
final class JwtVerifier {
  /// Creates a verifier.
  JwtVerifier({
    required this.jwks,
    required this.expectedIssuer,
    this.expectedAudience = 'authenticated',
    this.leeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// The source of the signing keys.
  final JwksProvider jwks;

  /// The issuer every token must declare.
  final String expectedIssuer;

  /// The audience every token must declare.
  final String expectedAudience;

  /// The tolerated clock drift on the time based claims.
  final Duration leeway;

  final DateTime Function() _clock;

  /// Verifies [token] and returns the authenticated caller.
  Future<AuthContext> verify(String token) async {
    final List<String> parts = token.split('.');
    if (parts.length != 3) {
      throw const UnauthorizedException(
        message: 'Le jeton d\'authentification est mal formé.',
      );
    }

    final Map<String, dynamic> header = _decodeSegment(parts[0]);
    if (header['alg'] != 'RS256') {
      throw const UnauthorizedException(
        message:
            'Le jeton d\'authentification utilise un algorithme non '
            'supporté.',
      );
    }
    final Object? kid = header['kid'];
    if (kid is! String || kid.isEmpty) {
      throw const UnauthorizedException(
        message: 'Le jeton d\'authentification ne désigne aucune clé.',
      );
    }

    final Map<String, dynamic> claims = _decodeSegment(parts[1]);
    final JsonWebKey key = await _resolveKey(kid);

    final List<int> signed = utf8.encode('${parts[0]}.${parts[1]}');
    final List<int> signature;
    try {
      signature = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      throw const UnauthorizedException(
        message: 'La signature du jeton d\'authentification est illisible.',
      );
    }

    if (!RsaVerifier.verify(key.raw, signed, signature)) {
      throw const UnauthorizedException(
        message: 'La signature du jeton d\'authentification est invalide.',
      );
    }

    _validateClaims(claims);
    return AuthContext(
      userId: _requireSubject(claims),
      email: claims['email'] is String ? claims['email']! as String : '',
      claims: Map<String, dynamic>.unmodifiable(claims),
    );
  }

  Future<JsonWebKey> _resolveKey(String kid) async {
    Map<String, JsonWebKey> keys = await jwks.keys();
    JsonWebKey? key = keys[kid];
    if (key == null) {
      keys = await jwks.refresh();
      key = keys[kid];
    }
    if (key == null) {
      throw const UnauthorizedException(
        message: 'La clé de signature du jeton est inconnue.',
      );
    }
    return key;
  }

  void _validateClaims(Map<String, dynamic> claims) {
    final DateTime now = _clock();

    final Object? expiration = claims['exp'];
    if (expiration is! int) {
      throw const UnauthorizedException(
        message:
            'Le jeton d\'authentification ne porte pas de date '
            'd\'expiration.',
      );
    }
    final DateTime expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiration * 1000,
      isUtc: true,
    );
    if (now.isAfter(expiresAt.add(leeway))) {
      throw const TokenExpiredException();
    }

    final Object? notBefore = claims['nbf'];
    if (notBefore is int) {
      final DateTime startsAt = DateTime.fromMillisecondsSinceEpoch(
        notBefore * 1000,
        isUtc: true,
      );
      if (now.add(leeway).isBefore(startsAt)) {
        throw const UnauthorizedException(
          message: 'Le jeton d\'authentification n\'est pas encore valide.',
        );
      }
    }

    final Object? issuer = claims['iss'];
    if (issuer != expectedIssuer) {
      throw const UnauthorizedException(
        message: 'Le jeton d\'authentification provient d\'une autre source.',
      );
    }

    if (!_hasAudience(claims['aud'], expectedAudience)) {
      throw const UnauthorizedException(
        message:
            'Le jeton d\'authentification ne cible pas cette '
            'application.',
      );
    }
  }

  static bool _hasAudience(Object? audience, String expected) {
    if (audience is String) return audience == expected;
    if (audience is List) {
      return audience.any((Object? value) => value == expected);
    }
    return false;
  }

  static String _requireSubject(Map<String, dynamic> claims) {
    final Object? subject = claims['sub'];
    if (subject is! String || subject.isEmpty) {
      throw const UnauthorizedException(
        message: 'Le jeton d\'authentification ne désigne aucun compte.',
      );
    }
    return subject;
  }

  static Map<String, dynamic> _decodeSegment(String segment) {
    try {
      final Object? decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segment))),
      );
      if (decoded is! Map<String, dynamic>) {
        throw const UnauthorizedException(
          message: 'Le jeton d\'authentification est mal formé.',
        );
      }
      return decoded;
    } on FormatException {
      throw const UnauthorizedException(
        message: 'Le jeton d\'authentification est mal formé.',
      );
    }
  }
}
