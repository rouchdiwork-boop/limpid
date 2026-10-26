/// L'état de la double authentification d'un compte, tel que le client le
/// voit.
final class TwoFactorState {
  /// Crée un état.
  const TwoFactorState({
    required this.isEnrolled,
    required this.isEnabled,
    required this.isRequired,
  });

  /// Indique si le compte a un secret enregistré.
  final bool isEnrolled;

  /// Indique si la double authentification est active.
  final bool isEnabled;

  /// Indique si la formule du compte l'exige.
  final bool isRequired;

  /// La représentation JSON de l'état.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enrolled': isEnrolled,
      'enabled': isEnabled,
      'required': isRequired,
    };
  }
}

/// L'enrôlement d'un compte dans la double authentification.
///
/// Le secret est rendu une seule fois, au moment de l'inscription : il
/// n'est actif qu'après la confirmation d'un premier code.
final class TwoFactorEnrollment {
  /// Crée un enrôlement.
  const TwoFactorEnrollment({
    required this.secret,
    required this.otpauthUrl,
    required this.digits,
    required this.seconds,
  });

  /// Le secret partagé, encodé en base32.
  final String secret;

  /// L'URL d'inscription de l'application d'authentification.
  final String otpauthUrl;

  /// Le nombre de chiffres des codes.
  final int digits;

  /// La durée d'un pas de l'horloge, en secondes.
  final int seconds;

  /// La représentation JSON de l'enrôlement.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'secret': secret,
      'otpauth_url': otpauthUrl,
      'digits': digits,
      'period_seconds': seconds,
    };
  }
}

/// La réussite d'une vérification du second facteur.
final class TwoFactorVerification {
  /// Crée une vérification.
  const TwoFactorVerification({
    required this.proof,
    required this.expiresAt,
    required this.method,
  });

  /// La preuve du second facteur, à renvoyer dans l'en-tête de la requête.
  final String proof;

  /// L'instant d'expiration de la preuve.
  final DateTime expiresAt;

  /// Le moyen utilisé : `totp` ou `recovery`.
  final String method;

  /// La représentation JSON de la vérification.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'verified': true,
      'proof': proof,
      'method': method,
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }
}
