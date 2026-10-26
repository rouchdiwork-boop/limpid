import 'promo_code_store.dart';

/// L'implémentation en mémoire du port [PromoCodeStore].
///
/// La réservation y est atomique : la lecture du code, la vérification des
/// quotas et l'écriture ont lieu sans interruption, donc deux réservations
/// concurrentes ne peuvent pas dépasser le quota d'un code.
final class InMemoryPromoCodeStore implements PromoCodeStore {
  /// Crée un port vide.
  InMemoryPromoCodeStore();

  final Map<String, PromoCodeRecord> _codes = <String, PromoCodeRecord>{};
  final Map<String, int> _usagesByAccount = <String, int>{};

  @override
  Future<PromoCodeRecord?> findByCode(String code) async {
    return _codes[normalizePromoCode(code)];
  }

  @override
  Future<void> save(PromoCodeRecord record) async {
    _codes[normalizePromoCode(record.code)] = record;
  }

  @override
  Future<PromoReservation> reserve({
    required String code,
    required String userId,
    required DateTime at,
  }) async {
    final String key = normalizePromoCode(code);
    final PromoCodeRecord? record = _codes[key];
    if (record == null) {
      return const PromoReservationRefused(PromoRefusalReason.unknown);
    }
    if (record.isExpiredAt(at)) {
      return const PromoReservationRefused(PromoRefusalReason.expired);
    }
    if (_usagesByAccount[_usageKey(key, userId)] != null &&
        _usagesByAccount[_usageKey(key, userId)]! >= record.maxUsesPerAccount) {
      return const PromoReservationRefused(PromoRefusalReason.alreadyUsed);
    }
    if (record.isExhausted) {
      return const PromoReservationRefused(PromoRefusalReason.exhausted);
    }

    // La reservation est ecrite sans interruption : le quota du code et le
    // compteur du compte bougent ensemble.
    _codes[key] = _withUses(record, record.uses + 1);
    final String usageKey = _usageKey(key, userId);
    _usagesByAccount[usageKey] = (_usagesByAccount[usageKey] ?? 0) + 1;
    return PromoReservationGranted(_codes[key]!);
  }

  /// La clé du compteur d'usage d'un compte pour un code.
  static String _usageKey(String code, String userId) => '$code::$userId';

  /// Le code, avec un compteur d'utilisations.
  static PromoCodeRecord _withUses(PromoCodeRecord record, int uses) {
    return PromoCodeRecord(
      code: record.code,
      discountType: record.discountType,
      value: record.value,
      currency: record.currency,
      maxUses: record.maxUses,
      maxUsesPerAccount: record.maxUsesPerAccount,
      expiresAt: record.expiresAt,
      createdAt: record.createdAt,
      uses: uses,
    );
  }
}
