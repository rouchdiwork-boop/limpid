import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../auth/totp.dart';

/// La tolérance de l'horodatage de la signature.
///
/// Stripe recommande cinq minutes : au-delà, une signature rejouée est
/// refusée, et une livraison retardée par un incident réseau court.
const Duration defaultStripeSignatureTolerance = Duration(minutes: 5);

/// Le verdict de la vérification d'une signature Stripe.
enum StripeSignatureVerdict {
  /// La signature est valide : la livraison vient bien de Stripe.
  valid,

  /// L'en-tête est absent, mal formé, ou ne porte aucune signature.
  malformed,

  /// L'horodatage de la signature est hors de la tolérance.
  outdated,

  /// La signature ne correspond ni au corps, ni au secret.
  mismatched,
}

/// La vérification de la signature d'une livraison Stripe.
///
/// Stripe signe `horodatage + "." + corps` en HMAC-SHA256 avec le secret du
/// point de rappel, et porte le résultat dans l'en-tête `Stripe-Signature`,
/// sous la forme `t=<horodatage>,v1=<signature>`.
///
/// La vérification refuse trois cas : un en-tête mal formé, un horodatage
/// hors de la tolérance, et une signature qui ne correspond pas. Les trois
/// verdicts se traduisent par le même refus côté HTTP : l'appelant n'apprend
/// pas quelle partie de la signature il a devinée juste.
///
/// La comparaison est faite à temps constant : le temps mis à rejeter une
/// signature ne dépend pas de la position du premier octet erroné.
final class StripeSignatureVerifier {
  /// Crée un vérificateur.
  const StripeSignatureVerifier({
    required this.secret,
    this.tolerance = defaultStripeSignatureTolerance,
  });

  /// Le secret du point de rappel Stripe.
  final String secret;

  /// La tolérance de l'horodatage de la signature.
  final Duration tolerance;

  /// Vérifie la signature portée par [header] sur le corps [payload].
  ///
  /// Le corps est vérifié **tel quel** : le re-sérialiser changerait la
  /// signature, et Stripe ne retient que le corps qu'il a envoyé.
  ///
  /// [now] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  StripeSignatureVerdict verify({
    required String? header,
    required List<int> payload,
    DateTime? now,
  }) {
    final _SignatureParts? parts = _parse(header);
    if (parts == null) return StripeSignatureVerdict.malformed;
    final DateTime moment = (now ?? DateTime.now()).toUtc();
    final Duration age = moment.difference(parts.signedAt);
    if (age.abs() > tolerance) return StripeSignatureVerdict.outdated;
    final List<int> expected = _sign(parts.timestamp, payload);
    for (final List<int> candidate in parts.signatures) {
      if (constantTimeEquals(expected, candidate)) {
        return StripeSignatureVerdict.valid;
      }
    }
    return StripeSignatureVerdict.mismatched;
  }

  /// La signature attendue pour le corps [payload] à l'instant [timestamp].
  ///
  /// L'horodatage est repris tel que Stripe l'a écrit : c'est la chaîne
  /// signée, pas sa relecture, qui fait la signature.
  List<int> _sign(String timestamp, List<int> payload) {
    final Hmac hmac = Hmac(sha256, utf8.encode(secret));
    final List<int> prefix = utf8.encode('$timestamp.');
    return hmac.convert(<int>[...prefix, ...payload]).bytes;
  }

  /// Les parties de l'en-tête de signature, `null` quand il est mal formé.
  static _SignatureParts? _parse(String? header) {
    if (header == null) return null;
    final String trimmed = header.trim();
    if (trimmed.isEmpty) return null;
    String? timestamp;
    final List<List<int>> signatures = <List<int>>[];
    for (final String chunk in trimmed.split(',')) {
      final int separator = chunk.indexOf('=');
      // Un morceau sans séparateur est ignoré : Stripe peut ajouter un
      // jour un scheme de signature supplémentaire, et une signature
      // valide ne doit pas dépendre des morceaux inconnus.
      if (separator <= 0) continue;
      final String key = chunk.substring(0, separator).trim();
      final String value = chunk.substring(separator + 1).trim();
      if (key == 't') {
        timestamp = value;
      } else if (key == 'v1') {
        final List<int>? bytes = _decodeHex(value);
        if (bytes == null) return null;
        signatures.add(bytes);
      }
    }
    if (timestamp == null || timestamp.isEmpty) return null;
    if (signatures.isEmpty) return null;
    final int? seconds = int.tryParse(timestamp);
    if (seconds == null) return null;
    return _SignatureParts(
      timestamp: timestamp,
      signedAt: DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ),
      signatures: List<List<int>>.unmodifiable(signatures),
    );
  }

  /// Les octets de la valeur hexadécimale [value], `null` quand elle est
  /// mal formée.
  static List<int>? _decodeHex(String value) {
    if (value.isEmpty || value.length.isOdd) return null;
    final List<int> bytes = <int>[];
    for (int index = 0; index < value.length; index += 2) {
      final int? high = _hexDigit(value.codeUnitAt(index));
      final int? low = _hexDigit(value.codeUnitAt(index + 1));
      if (high == null || low == null) return null;
      bytes.add(high * 16 + low);
    }
    return bytes;
  }

  /// La valeur d'un chiffre hexadécimal, `null` quand ce n'en est pas un.
  static int? _hexDigit(int code) {
    if (code >= 0x30 && code <= 0x39) return code - 0x30;
    if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
    if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
    return null;
  }
}

/// Les parties de l'en-tête de signature, une fois lues.
final class _SignatureParts {
  const _SignatureParts({
    required this.timestamp,
    required this.signedAt,
    required this.signatures,
  });

  /// L'horodatage écrit par Stripe, tel quel.
  final String timestamp;

  /// L'horodatage de la signature, en temps universel.
  final DateTime signedAt;

  /// Les signatures candidates, en octets.
  final List<List<int>> signatures;
}
