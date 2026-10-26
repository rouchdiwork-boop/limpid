import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_context.dart';
import '../auth/totp.dart';
import '../auth/two_factor_guard.dart';
import '../auth/two_factor_proof.dart';
import '../db/plan_lookup.dart';
import '../db/two_factor_database.dart';
import '../errors/app_exception.dart';
import 'two_factor_models.dart';

export '../db/plan_lookup.dart';

/// Les formules sur lesquelles la double authentification est obligatoire
/// (D-19).
///
/// Les noms sont ceux du domaine partagé : `pro` et `studio`. La lecture est
/// normalisée, la casse et les accents n'ont donc pas d'importance.
const Set<String> plansRequiringTwoFactor = <String>{'pro', 'studio'};

/// Le nom de la formule gratuite.
const String freePlanName = 'gratuit';

/// Le nombre de codes de récupération rendus à l'activation.
const int recoveryCodeCount = 10;

/// Le nombre de caractères d'un code de récupération.
const int recoveryCodeLength = 16;

/// L'alphabet des codes de récupération.
///
/// Les caractères ambigus sont exclus : un code recopié dans un carnet
/// reste lisible.
const String _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Les lettres accentuées et leur équivalent non accentué.
const Map<String, String> _diacritics = <String, String>{
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Le service de la double authentification.
///
/// Le service porte les règles : le secret n'est actif qu'après la
/// confirmation d'un premier code, les codes de récupération ne servent
/// qu'une fois, la formule du compte décide si la double authentification
/// est obligatoire, et la preuve du second facteur est une signature faite
/// avec le secret du compte.
final class TwoFactorService implements TwoFactorGuard {
  /// Crée un service.
  ///
  /// [planOf] lit la formule d'un compte ; [clock] donne l'instant
  /// courant, ce qui permet de tester les fenêtres de tolérance.
  TwoFactorService({
    required this.database,
    required this.planOf,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// La base des secrets et des codes de récupération.
  final TwoFactorDatabase database;

  /// La lecture de la formule du compte.
  final PlanLookup planOf;

  /// L'heure courante, en UTC.
  final DateTime Function() _clock;

  /// L'état de la double authentification du compte [userId].
  Future<TwoFactorState> stateOf(String userId) async {
    final TwoFactorRecord? record = await database.findByUserId(userId);
    return TwoFactorState(
      isEnrolled: record != null,
      isEnabled: record?.isEnabled ?? false,
      isRequired: await requiresTwoFactor(userId),
    );
  }

  /// Indique si la formule du compte [userId] exige la double
  /// authentification.
  Future<bool> requiresTwoFactor(String userId) async {
    final String? plan = await planOf(userId);
    return plansRequiringTwoFactor.contains(normalizePlan(plan));
  }

  /// Inscrit le compte [userId] dans la double authentification.
  ///
  /// Le secret généré n'est actif qu'après la confirmation d'un premier
  /// code : l'inscription ne verrouille jamais l'auteur hors de son propre
  /// compte.
  Future<TwoFactorEnrollment> enroll({
    required String userId,
    required String email,
  }) async {
    final TwoFactorRecord? existing = await database.findByUserId(userId);
    if (existing != null && existing.isEnabled) {
      throw const ConflictException(
        message:
            'La double authentification est déjà active sur ce compte : '
            'désactivez-la avant de la reconfigurer.',
      );
    }

    final String secret = generateTotpSecret();
    await database.savePendingSecret(
      userId: userId,
      secret: secret,
      createdAt: _clock(),
    );
    return TwoFactorEnrollment(
      secret: secret,
      otpauthUrl: buildOtpauthUrl(email: email, secret: secret),
      digits: totpDigits,
      seconds: totpPeriod.inSeconds,
    );
  }

  /// Confirme l'inscription du compte [userId] et active la double
  /// authentification.
  ///
  /// Renvoie les codes de récupération, une seule fois : ils ne sont
  /// jamais rendus à nouveau.
  Future<List<String>> confirm({
    required String userId,
    required String code,
  }) async {
    final TwoFactorRecord? record = await database.findByUserId(userId);
    if (record == null) {
      throw const ConflictException(
        message:
            "Aucune inscription en attente : relancez l'enrôlement avant "
            'de confirmer.',
      );
    }
    if (record.isEnabled) {
      throw const ConflictException(
        message: 'La double authentification est déjà active sur ce compte.',
      );
    }
    if (!verifyTotpCode(record.secret, code, _clock())) {
      throw const ValidationException(
        field: 'code',
        message: 'Le code est invalide ou expiré.',
      );
    }

    final List<String> codes = generateRecoveryCodes();
    await database.activate(
      userId: userId,
      enabledAt: _clock(),
      codeHashes: <String>[
        for (final String recoveryCode in codes) hashRecoveryCode(recoveryCode),
      ],
    );
    return codes;
  }

  /// Vérifie le second facteur [code] du compte [userId].
  ///
  /// Le code est soit un code TOTP, soit un code de récupération. Un code
  /// de récupération est consommé : il ne sert plus.
  Future<TwoFactorVerification> verify({
    required String userId,
    required String code,
  }) async {
    final TwoFactorRecord? record = await database.findByUserId(userId);
    if (record == null || !record.isEnabled) {
      throw const ConflictException(
        message:
            "La double authentification n'est pas active sur ce compte : "
            "inscrivez-vous d'abord.",
      );
    }

    final DateTime now = _clock();
    final String candidate = code.trim();
    final String method = _isTotpCode(candidate)
        ? _verifyTotp(record, candidate, now)
        : await _verifyRecoveryCode(userId, candidate, now);

    final DateTime expiresAt = now.add(twoFactorProofLifetime);
    return TwoFactorVerification(
      proof: issueTwoFactorProof(
        secret: record.secret,
        userId: userId,
        expiresAt: expiresAt,
      ),
      expiresAt: expiresAt,
      method: method,
    );
  }

  /// Désactive la double authentification du compte [userId].
  ///
  /// Le secret est effacé et les codes de récupération sont invalidés.
  Future<void> disable(String userId) async {
    await database.disable(userId: userId);
  }

  @override
  Future<void> verifySecondFactor(AuthContext auth, Request request) async {
    final TwoFactorRecord? record = await database.findByUserId(auth.userId);
    if (record == null || !record.isEnabled) {
      if (await requiresTwoFactor(auth.userId)) {
        throw const ForbiddenException(
          message:
              'Votre formule exige la double authentification : activez-la '
              "pour continuer à utiliser l'API.",
          details: <String, Object?>{'feature': 'two_factor'},
        );
      }
      return;
    }

    final String? proof = request.headers[twoFactorProofHeader];
    if (proof == null || proof.trim().isEmpty) {
      throw const UnauthorizedException(
        message:
            'La double authentification est active : prouvez le second '
            'facteur pour continuer.',
        details: <String, Object?>{
          'feature': 'two_factor',
          'reason': 'missing_proof',
        },
      );
    }
    if (!verifyTwoFactorProof(
      secret: record.secret,
      userId: auth.userId,
      proof: proof,
      now: _clock(),
    )) {
      throw const UnauthorizedException(
        message: 'La preuve du second facteur est invalide ou expirée.',
        details: <String, Object?>{
          'feature': 'two_factor',
          'reason': 'invalid_proof',
        },
      );
    }
  }

  /// Vérifie un code TOTP et renvoie le moyen utilisé.
  String _verifyTotp(TwoFactorRecord record, String code, DateTime now) {
    if (!verifyTotpCode(record.secret, code, now)) {
      throw const UnauthorizedException(
        message: 'Le code de vérification est invalide.',
        details: <String, Object?>{
          'feature': 'two_factor',
          'reason': 'invalid_code',
        },
      );
    }
    return 'totp';
  }

  /// Consomme un code de récupération et renvoie le moyen utilisé.
  Future<String> _verifyRecoveryCode(
    String userId,
    String code,
    DateTime now,
  ) async {
    final bool consumed = await database.consumeRecoveryCode(
      userId: userId,
      codeHash: hashRecoveryCode(code),
      usedAt: now,
    );
    if (!consumed) {
      throw const UnauthorizedException(
        message: 'Le code de vérification est invalide.',
        details: <String, Object?>{
          'feature': 'two_factor',
          'reason': 'invalid_code',
        },
      );
    }
    return 'recovery';
  }
}

/// Normalise le nom d'une formule.
///
/// La formule est comparée sans accent et sans casse : `Pro`, `pro` et
/// `PRO` désignent la même formule. Une formule absente vaut la formule
/// gratuite.
String normalizePlan(String? plan) {
  if (plan == null) return freePlanName;
  final String lowered = plan.trim().toLowerCase();
  final StringBuffer buffer = StringBuffer();
  for (final int unit in lowered.codeUnits) {
    final String character = String.fromCharCode(unit);
    buffer.write(_diacritics[character] ?? character);
  }
  return buffer.toString();
}

/// Construit l'URL d'inscription de l'application d'authentification.
///
/// L'URL suit la forme `otpauth://totp/Limpid:<email>?secret=...`.
String buildOtpauthUrl({
  required String email,
  required String secret,
  String issuer = 'Limpid',
}) {
  return Uri(
    scheme: 'otpauth',
    host: 'totp',
    path: '/$issuer:$email',
    queryParameters: <String, String>{
      'secret': secret,
      'issuer': issuer,
      'algorithm': 'SHA1',
      'digits': '$totpDigits',
      'period': '${totpPeriod.inSeconds}',
    },
  ).toString();
}

/// Génère les codes de récupération d'un compte.
///
/// Les codes sont tirés au hasard par un générateur cryptographique : un
/// code devinable donnerait le compte entier.
List<String> generateRecoveryCodes({int count = recoveryCodeCount}) {
  final Random random = Random.secure();
  return List<String>.generate(
    count,
    (_) => _recoveryCode(random),
    growable: false,
  );
}

/// Calcule l'empreinte d'un code de récupération.
///
/// Seule l'empreinte est enregistrée : une fuite de la base ne donne
/// aucun code utilisable.
String hashRecoveryCode(String code) {
  return sha256.convert(utf8.encode(normalizeRecoveryCode(code))).toString();
}

/// Normalise un code de récupération : en majuscules, sans séparateur.
String normalizeRecoveryCode(String code) {
  final StringBuffer buffer = StringBuffer();
  for (final int unit in code.trim().toUpperCase().codeUnits) {
    if (unit == 0x2d || unit == 0x20) continue;
    buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

/// Tire un code de récupération.
///
/// Le code est groupé par quatre caractères, ce qui le rend lisible quand
/// l'utilisateur le recopie depuis l'écran.
String _recoveryCode(Random random) {
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < recoveryCodeLength; index++) {
    if (index > 0 && index % 4 == 0) buffer.write('-');
    buffer.write(_recoveryAlphabet[random.nextInt(_recoveryAlphabet.length)]);
  }
  return buffer.toString();
}

/// Indique si [code] a la forme d'un code TOTP.
bool _isTotpCode(String code) {
  if (code.length != totpDigits) return false;
  for (final int unit in code.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return true;
}
