/// Le type d'une remise.
///
/// La liste est **fermée** : une remise est un pourcentage ou un montant
/// fixe. Une remise en points de fidélité demanderait un autre compteur,
/// donc une autre table.
enum PromoDiscountType {
  /// Une remise en pourcentage du prix du livre.
  ///
  /// La valeur est un pourcentage en millièmes : 2 500 millièmes font
  /// 25 %.
  percent('percent'),

  /// Une remise d'un montant fixe, en centimes.
  amount('amount');

  const PromoDiscountType(this.key);

  /// Le nom technique du type, écrit dans la base.
  final String key;

  /// Le type nommé [raw], `null` quand il est inconnu.
  static PromoDiscountType? parse(String raw) {
    final String normalized = raw.trim().toLowerCase();
    for (final PromoDiscountType type in PromoDiscountType.values) {
      if (type.key == normalized) return type;
    }
    return null;
  }
}

/// Un code promo.
///
/// Le code porte une remise, une échéance et deux quotas : le nombre
/// d'utilisations totales, et le nombre d'utilisations par compte.
final class PromoCodeRecord {
  /// Crée un code promo.
  const PromoCodeRecord({
    required this.code,
    required this.discountType,
    required this.value,
    required this.currency,
    required this.maxUses,
    required this.maxUsesPerAccount,
    required this.expiresAt,
    required this.createdAt,
    this.uses = 0,
  });

  /// L'identifiant du code, tel que l'acheteur le saisit.
  ///
  /// Le code est comparé sans tenir compte de la casse et des espaces
  /// autour : `Bienvenue` et `bienvenue` sont le même code.
  final String code;

  /// Le type de la remise.
  final PromoDiscountType discountType;

  /// La valeur de la remise.
  ///
  /// La valeur est un pourcentage en millièmes pour le type `percent`, et
  /// un montant en centimes pour le type `amount`.
  final int value;

  /// La devise du montant de la remise.
  final String currency;

  /// Le nombre d'utilisations autorisées au total.
  final int maxUses;

  /// Le nombre d'utilisations autorisées par compte.
  final int maxUsesPerAccount;

  /// L'instant d'expiration du code.
  final DateTime expiresAt;

  /// L'instant de la création du code.
  final DateTime createdAt;

  /// Le nombre d'utilisations déjà accordées.
  final int uses;

  /// Le code est-il expiré à l'instant [now] ?
  ///
  /// L'échéance est inclusive : à l'instant exact de l'échéance, le code
  /// est expiré.
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  /// Le code est-il épuisé ?
  bool get isExhausted => uses >= maxUses;

  /// La représentation JSON du code, envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'discount_type': discountType.key,
      'value': value,
      'currency': currency,
      'max_uses': maxUses,
      'uses': uses,
      'max_uses_per_account': maxUsesPerAccount,
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }
}

/// La raison pour laquelle un code promo est refusé.
enum PromoRefusalReason {
  /// Le code n'existe pas.
  unknown('unknown'),

  /// Le code est passé sa date d'expiration.
  expired('expired'),

  /// Le code a atteint son nombre maximal d'utilisations.
  exhausted('exhausted'),

  /// Le compte a déjà utilisé ce code.
  alreadyUsed('already_used');

  const PromoRefusalReason(this.key);

  /// Le nom technique de la raison, stable dans les journaux.
  final String key;
}

/// L'issue de la réservation d'un code promo.
sealed class PromoReservation {
  /// Crée une issue.
  const PromoReservation();
}

/// La réservation est accordée : le code peut être appliqué.
final class PromoReservationGranted extends PromoReservation {
  /// Crée une réservation accordée.
  const PromoReservationGranted(this.code);

  /// Le code réservé.
  final PromoCodeRecord code;
}

/// La réservation est refusée : le code ne peut pas être appliqué.
final class PromoReservationRefused extends PromoReservation {
  /// Crée une réservation refusée.
  const PromoReservationRefused(this.reason);

  /// La raison du refus.
  final PromoRefusalReason reason;
}

/// La forme normalisée d'un code promo.
///
/// Le code est comparé sans tenir compte de la casse ni des espaces
/// autour : `Bienvenue` et `bienvenue` sont le même code. La forme
/// normalisée est la clé de stockage : les trois implémentations du port
/// s'en servent pour retrouver le code.
String normalizePromoCode(String code) => code.trim().toLowerCase();

/// Le port de persistance des codes promo.
///
/// La réservation est **atomique** : deux commandes concurrentes ne
/// peuvent pas dépasser le quota d'utilisations d'un code. Le port expose
/// donc une seule opération de réservation, et non une lecture suivie
/// d'une écriture.
abstract interface class PromoCodeStore {
  /// Le code nommé [code], `null` quand il n'existe pas.
  Future<PromoCodeRecord?> findByCode(String code);

  /// Enregistre un code promo.
  Future<void> save(PromoCodeRecord record);

  /// Réserve une utilisation du code [code] pour le compte [userId].
  ///
  /// La réservation décrémente le quota du code **et** compte l'usage du
  /// compte, en une seule opération : le code ne peut pas dépasser son
  /// quota, et un compte ne peut pas l'utiliser plus de fois qu'il n'y a
  /// droit.
  Future<PromoReservation> reserve({
    required String code,
    required String userId,
    required DateTime at,
  });
}
