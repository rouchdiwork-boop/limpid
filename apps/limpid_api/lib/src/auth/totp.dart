import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// L'alphabet du base32 (RFC 4648), sans le caractère de remplissage.
///
/// Le remplissage est omis parce que les applications d'authentification
/// attendent le secret sans lui.
const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Le nombre d'octets d'un secret TOTP généré.
///
/// La longueur est celle recommandée par la RFC 4226 pour un HMAC-SHA1.
const int totpSecretLength = 20;

/// Le nombre de chiffres d'un code TOTP.
const int totpDigits = 6;

/// La durée d'un pas de l'horloge TOTP.
const Duration totpPeriod = Duration(seconds: 30);

/// Le nombre de pas acceptés avant et après le pas courant.
///
/// Un pas de chaque côté absorbe la dérive entre l'horloge du serveur et
/// celle du téléphone.
const int totpWindow = 1;

/// Encode [bytes] en base32 (RFC 4648), sans le remplissage.
String encodeBase32(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  int accumulator = 0;
  int bits = 0;
  for (final int byte in bytes) {
    accumulator = (accumulator << 8) | (byte & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buffer.write(_base32Alphabet[(accumulator >> bits) & 0x1f]);
    }
    accumulator &= (1 << bits) - 1;
  }
  if (bits > 0) {
    buffer.write(_base32Alphabet[(accumulator << (5 - bits)) & 0x1f]);
  }
  return buffer.toString();
}

/// Décode le secret [encoded], écrit en base32.
///
/// Les majuscules, les minuscules, le remplissage et les espaces sont
/// acceptés : l'utilisateur peut saisir le secret à la main.
///
/// Lève une [FormatException] quand le secret porte un caractère qui n'est
/// pas du base32.
List<int> decodeBase32(String encoded) {
  final List<int> bytes = <int>[];
  int accumulator = 0;
  int bits = 0;
  for (final int unit in encoded.toUpperCase().codeUnits) {
    if (unit == 0x3d) break;
    if (unit == 0x20 || unit == 0x09) continue;
    final int index = _base32Alphabet.indexOf(String.fromCharCode(unit));
    if (index < 0) {
      throw FormatException('Invalid base32 character in the secret.');
    }
    accumulator = (accumulator << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((accumulator >> bits) & 0xff);
      accumulator &= (1 << bits) - 1;
    }
  }
  return bytes;
}

/// Génère un secret aléatoire de [length] octets, encodé en base32.
///
/// Le générateur est cryptographique : un secret faible imiterait un
/// facteur devinable.
String generateTotpSecret({int length = totpSecretLength, Random? random}) {
  final Random source = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(
    length,
    (_) => source.nextInt(256),
    growable: false,
  );
  return encodeBase32(bytes);
}

/// Calcule le code TOTP du secret [secret] à l'instant [time].
///
/// L'algorithme suit la RFC 6238 : le compteur est le nombre de pas
/// écoulés depuis l'époque, le HMAC-SHA1 du compteur est tronqué selon la
/// RFC 4226 et le résultat est réduit modulo le nombre de chiffres
/// demandé.
String totpCode(
  String secret,
  DateTime time, {
  int digits = totpDigits,
  Duration period = totpPeriod,
}) {
  final List<int> key = decodeBase32(secret);
  final int counter =
      time.toUtc().millisecondsSinceEpoch ~/ period.inMilliseconds;
  final ByteData message = ByteData(8)..setUint64(0, counter);
  final Digest digest = Hmac(sha1, key).convert(message.buffer.asUint8List());
  final List<int> bytes = digest.bytes;
  final int offset = bytes[bytes.length - 1] & 0x0f;
  final int binary =
      ((bytes[offset] & 0x7f) << 24) |
      ((bytes[offset + 1] & 0xff) << 16) |
      ((bytes[offset + 2] & 0xff) << 8) |
      (bytes[offset + 3] & 0xff);
  final int modulo = pow(10, digits).toInt();
  return (binary % modulo).toString().padLeft(digits, '0');
}

/// Indique si [code] est le code du secret [secret] à l'instant [time].
///
/// Les pas [window] avant et après le pas courant sont acceptés : le code
/// reste valide un peu avant son apparition et un peu après sa
/// disparition, le temps que le téléphone rattrape l'horloge du serveur.
bool verifyTotpCode(
  String secret,
  String code,
  DateTime time, {
  int digits = totpDigits,
  Duration period = totpPeriod,
  int window = totpWindow,
}) {
  final String candidate = code.trim();
  if (candidate.length != digits) return false;
  if (!_isDigits(candidate)) return false;
  for (int step = -window; step <= window; step++) {
    final String expected = totpCode(
      secret,
      time.toUtc().add(period * step),
      digits: digits,
      period: period,
    );
    if (constantTimeEquals(expected.codeUnits, candidate.codeUnits)) {
      return true;
    }
  }
  return false;
}

/// Compare [left] et [right] sans révéler leur contenu par le temps pris.
///
/// La comparaison parcourt toujours les deux suites en entier et accumule
/// les différences : le temps de la comparaison ne dépend pas du nombre de
/// caractères qui coïncident.
///
/// Le paquet `crypto` de la version utilisée par l'API n'expose pas
/// `constantTimeBytesEquality` : l'API le fournit elle-même.
bool constantTimeEquals(List<int> left, List<int> right) {
  final int shortest = left.length < right.length ? left.length : right.length;
  int mismatch = left.length == right.length ? 0 : 1;
  for (int index = 0; index < shortest; index++) {
    mismatch |= left[index] ^ right[index];
  }
  return mismatch == 0;
}

/// Indique si [value] ne contient que des chiffres décimaux.
bool _isDigits(String value) {
  for (final int unit in value.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return value.isNotEmpty;
}
