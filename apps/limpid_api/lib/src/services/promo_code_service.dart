import '../db/promo_code_store.dart';
import '../errors/app_exception.dart';

/// La longueur maximale d'un code promo.
///
/// Le code est saisi à la main : au-delà de cette longueur, il ne sert
/// qu'à se tromper.
const int maxPromoCodeLength = 64;

/// Le total d'un pourcentage de remise, en millièmes.
///
/// 10 000 millièmes font 100 % : la remise porte alors le prix entier, et
/// le livre devient gratuit.
const int promoPercentTotal = 10000;

/// La remise appliquée par un code promo.
///
/// La remise est calculée sur le prix **du livre** : elle ne peut pas le
/// rendre négatif, et elle ne peut pas le dépasser. Un code de remise fixe
/// supérieure au prix vaut donc un livre gratuit.
final class PromoRedemption {
  /// Crée une remise.
  const PromoRedemption({
    required this.code,
    required this.discountType,
    required this.discountInCents,
    required this.priceInCents,
    required this.currency,
  });

  /// Le code utilisé.
  final String code;

  /// Le type de la remise.
  final PromoDiscountType discountType;

  /// La remise, en centimes.
  final int discountInCents;

  /// Le prix après la remise, en centimes.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// La représentation JSON de la remise.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'discount_type': discountType.key,
      'discount_cents': discountInCents,
      'price_cents': priceInCents,
      'currency': currency,
    };
  }
}

/// Le service des codes promo.
///
/// Le service **réserve** le code avant de rendre la remise : la
/// réservation décrémente le quota du code et compte l'usage du compte en
/// une seule opération. Un code expiré, épuisé ou déjà utilisé par le
/// compte est refusé, et le refus nomme la raison.
final class PromoCodeService {
  /// Crée un service sur le magasin [store].
  PromoCodeService({required this.store, DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  /// Le magasin des codes promo.
  final PromoCodeStore store;

  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Enregistre un code promo.
  ///
  /// Le code est normalisé : la casse et les espaces autour ne font pas
  /// deux codes. La valeur d'une remise en pourcentage est un pourcentage
  /// en millièmes, et celle d'une remise fixe un montant en centimes.
  Future<PromoCodeRecord> create({
    required String code,
    required PromoDiscountType discountType,
    required int value,
    required int maxUses,
    required int maxUsesPerAccount,
    required DateTime expiresAt,
    required String currency,
  }) async {
    final String normalized = normalizePromoCode(code);
    if (normalized.isEmpty) {
      throw ValidationException(
        field: 'code',
        message: 'Le code promo ne peut pas être vide.',
      );
    }
    if (normalized.length > maxPromoCodeLength) {
      throw ValidationException(
        field: 'code',
        message:
            'Le code promo ne peut pas dépasser $maxPromoCodeLength caractères.',
      );
    }
    if (maxUses < 1) {
      throw ValidationException(
        field: 'max_uses',
        message: 'Un code promo doit autoriser au moins une utilisation.',
      );
    }
    if (maxUsesPerAccount < 1) {
      throw ValidationException(
        field: 'max_uses_per_account',
        message:
            'Un code promo doit autoriser au moins une utilisation par compte.',
      );
    }
    if (discountType == PromoDiscountType.percent &&
        (value < 0 || value > promoPercentTotal)) {
      throw ValidationException(
        field: 'value',
        message:
            'Une remise en pourcentage doit être comprise entre 0 et '
            '$promoPercentTotal millièmes.',
      );
    }
    if (discountType == PromoDiscountType.amount && value < 0) {
      throw ValidationException(
        field: 'value',
        message: 'Une remise fixe ne peut pas être négative.',
      );
    }
    final PromoCodeRecord record = PromoCodeRecord(
      code: normalized,
      discountType: discountType,
      value: value,
      currency: currency,
      maxUses: maxUses,
      maxUsesPerAccount: maxUsesPerAccount,
      expiresAt: expiresAt.toUtc(),
      createdAt: _clock().toUtc(),
    );
    await store.save(record);
    return record;
  }

  /// Réserve le code [code] pour le compte [userId] et rend la remise.
  ///
  /// Le prix est celui du livre, en centimes : la remise s'y applique. Un
  /// code inconnu est une erreur de saisie (`400`), un code expiré,
  /// épuisé ou déjà utilisé est un conflit (`409`) : les deux messages
  /// nomment la raison du refus.
  Future<PromoRedemption> redeem({
    required String code,
    required String userId,
    required int priceInCents,
    required String currency,
  }) async {
    if (priceInCents < 0) {
      throw ArgumentError.value(
        priceInCents,
        'priceInCents',
        'Un prix ne peut pas être négatif.',
      );
    }
    final PromoReservation reservation = await store.reserve(
      code: code,
      userId: userId,
      at: _clock(),
    );
    return switch (reservation) {
      PromoReservationRefused(:final PromoRefusalReason reason) =>
        throw _refusal(reason, code),
      PromoReservationGranted(code: final PromoCodeRecord granted) => _apply(
        granted,
        priceInCents,
        currency,
      ),
    };
  }

  /// Rend l'usage du code [code] réservé par le compte [userId].
  ///
  /// La libération rend au code la place prise par la réservation : elle
  /// sert quand la commande n'a pas abouti — la session de paiement n'a pas
  /// pu être ouverte, ou elle a expiré sans que l'acheteur paie. Sans elle,
  /// le quota d'un code s'épuise sous des commandes abandonnées, et le code
  /// devient inutilisable pour les acheteurs qui, eux, paient.
  ///
  /// La libération est **idempotente** : rendre une place qui n'a pas été
  /// prise ne fait rien.
  Future<void> release({required String code, required String userId}) async {
    await store.release(code: code, userId: userId);
  }

  /// La remise du code [granted] sur le prix [priceInCents].
  PromoRedemption _apply(
    PromoCodeRecord granted,
    int priceInCents,
    String currency,
  ) {
    if (granted.currency != currency) {
      throw ValidationException(
        field: 'promo_code',
        message:
            'Le code « ${granted.code} » s\'applique à la devise '
            '${granted.currency} et non à $currency.',
        details: <String, Object?>{'field': 'promo_code'},
      );
    }
    final int raw = switch (granted.discountType) {
      PromoDiscountType.percent => priceInCents * granted.value ~/ 10000,
      PromoDiscountType.amount => granted.value,
    };
    // La remise ne rend jamais le prix negatif, et ne depasse jamais le
    // prix : un code de remise fixe superieure au prix vaut un livre
    // gratuit.
    final int bounded = raw < 0 ? 0 : (raw > priceInCents ? priceInCents : raw);
    return PromoRedemption(
      code: granted.code,
      discountType: granted.discountType,
      discountInCents: bounded,
      priceInCents: priceInCents - bounded,
      currency: currency,
    );
  }

  /// L'exception du refus, avec la raison nommée.
  static AppException _refusal(PromoRefusalReason reason, String code) {
    switch (reason) {
      case PromoRefusalReason.unknown:
        return ValidationException(
          field: 'promo_code',
          message: 'Le code promo « $code » n\'existe pas.',
          details: <String, Object?>{
            'field': 'promo_code',
            'reason': 'unknown',
          },
        );
      case PromoRefusalReason.expired:
        return ConflictException(
          message: 'Le code promo « $code » est expiré.',
          details: <String, Object?>{
            'field': 'promo_code',
            'reason': 'expired',
          },
        );
      case PromoRefusalReason.exhausted:
        return ConflictException(
          message:
              'Le code promo « $code » a atteint son quota d\'utilisations.',
          details: <String, Object?>{
            'field': 'promo_code',
            'reason': 'exhausted',
          },
        );
      case PromoRefusalReason.alreadyUsed:
        return ConflictException(
          message: 'Le code promo « $code » a déjà été utilisé par ce compte.',
          details: <String, Object?>{
            'field': 'promo_code',
            'reason': 'already_used',
          },
        );
    }
  }
}
