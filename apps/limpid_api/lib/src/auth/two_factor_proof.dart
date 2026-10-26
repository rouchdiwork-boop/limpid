import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'totp.dart';

/// L'en-tête qui porte la preuve du second facteur.
///
/// La preuve est un jeton court, signé avec le secret du compte : le client
/// l'envoie sur les requêtes authentifiées, le serveur la vérifie sans
/// interroger une table supplémentaire.
const String twoFactorProofHeader = 'x-limpid-2fa';

/// Le paramètre de requête qui porte la preuve du second facteur.
///
/// Un navigateur ne peut pas poser d'en-tête sur la poignée de main d'un
/// WebSocket : la connexion temps réel porte donc la preuve dans la
/// chaîne de requête.
const String twoFactorProofParameter = 'proof';

/// La durée de validité d'une preuve du second facteur.
const Duration twoFactorProofLifetime = Duration(minutes: 15);

/// Le domaine de séparation du jeton, qui lie la preuve à l'API.
const String _proofDomain = 'limpid-2fa-proof';

/// Construit la preuve du second facteur de [userId].
///
/// La preuve porte l'instant d'expiration et la signature de la paire
/// expiration / compte, calculée avec le secret partagé du compte. Elle
/// expire au bout de [twoFactorProofLifetime] et devient invalide dès que
/// le compte change de secret.
///
/// Le secret n'est jamais journalisé et la preuve ne sort jamais du
/// serveur : elle est rendue au client, qui la renvoie dans l'en-tête
/// [twoFactorProofHeader].
String issueTwoFactorProof({
  required String secret,
  required String userId,
  required DateTime expiresAt,
}) {
  final String payload = '${expiresAt.toUtc().millisecondsSinceEpoch}';
  final String signature = _signature(
    secret: secret,
    userId: userId,
    payload: payload,
  );
  return '${base64Url.encode(utf8.encode(payload))}'
      '.${base64Url.encode(utf8.encode(signature))}';
}

/// Indique si [proof] prouve le second facteur de [userId] à l'instant [now].
///
/// La preuve est rejetée quand elle est malformée, quand elle a expiré,
/// quand elle a été forgée ou quand elle a été émise pour un autre compte.
bool verifyTwoFactorProof({
  required String secret,
  required String userId,
  required String proof,
  required DateTime now,
}) {
  final List<String> parts = proof.split('.');
  if (parts.length != 2) return false;

  final String payload;
  final String signature;
  try {
    payload = utf8.decode(base64Url.decode(parts[0]));
    signature = utf8.decode(base64Url.decode(parts[1]));
  } on FormatException {
    return false;
  }

  final int? expiry = int.tryParse(payload);
  if (expiry == null) return false;
  final DateTime expiresAt = DateTime.fromMillisecondsSinceEpoch(
    expiry,
    isUtc: true,
  );
  if (!now.toUtc().isBefore(expiresAt)) return false;

  final String expected;
  try {
    expected = _signature(secret: secret, userId: userId, payload: payload);
  } on FormatException {
    // Le secret enregistré n'est pas du base32 : la preuve ne peut pas
    // être vérifiée, elle est donc rejetée.
    return false;
  }
  return constantTimeEquals(expected.codeUnits, signature.codeUnits);
}

/// Calcule la signature de la charge utile [payload].
///
/// La signature couvre le compte : une preuve ne peut pas être transportée
/// d'un compte à un autre.
String _signature({
  required String secret,
  required String userId,
  required String payload,
}) {
  final List<int> key = decodeBase32(secret);
  final Digest digest = Hmac(
    sha256,
    key,
  ).convert(utf8.encode('$_proofDomain|$userId|$payload'));
  return digest.toString();
}
