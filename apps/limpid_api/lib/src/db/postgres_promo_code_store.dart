import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';

import 'promo_code_store.dart';

/// L'implémentation Postgres du port [PromoCodeStore].
///
/// La réservation est atomique : l'usage du compte est inséré par une seule
/// instruction qui compte les usages déjà faits, et le quota du code est
/// décrémenté par une instruction conditionnelle. Deux commandes
/// concurrentes ne peuvent pas dépasser le quota, et un compte ne peut pas
/// utiliser un code plus de fois qu'il n'y a droit.
final class PostgresPromoCodeStore implements PromoCodeStore {
  /// Crée un magasin sur le pool [pool].
  PostgresPromoCodeStore(this._pool, {UlidGenerator? generator})
    : _generator = generator ?? UlidGenerator();

  /// Le pool de la base.
  final Pool<Object?> _pool;

  final UlidGenerator _generator;

  static const String _columns =
      'code, discount_type, value, currency, max_uses, uses, '
      'max_uses_per_account, expires_at, created_at';

  @override
  Future<PromoCodeRecord?> findByCode(String code) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM promo_codes WHERE code = \$1',
      parameters: <Object?>[normalizePromoCode(code)],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<void> save(PromoCodeRecord record) async {
    await _pool.execute(
      'INSERT INTO promo_codes '
      '(code, discount_type, value, currency, max_uses, uses, '
      'max_uses_per_account, expires_at, created_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9) '
      'ON CONFLICT (code) DO UPDATE SET '
      'discount_type = EXCLUDED.discount_type, '
      'value = EXCLUDED.value, '
      'currency = EXCLUDED.currency, '
      'max_uses = EXCLUDED.max_uses, '
      'uses = EXCLUDED.uses, '
      'max_uses_per_account = EXCLUDED.max_uses_per_account, '
      'expires_at = EXCLUDED.expires_at',
      parameters: <Object?>[
        normalizePromoCode(record.code),
        record.discountType.key,
        record.value,
        record.currency,
        record.maxUses,
        record.uses,
        record.maxUsesPerAccount,
        record.expiresAt,
        record.createdAt,
      ],
    );
  }

  @override
  Future<PromoReservation> reserve({
    required String code,
    required String userId,
    required DateTime at,
  }) async {
    final String key = normalizePromoCode(code);
    final PromoCodeRecord? record = await findByCode(key);
    if (record == null) {
      return const PromoReservationRefused(PromoRefusalReason.unknown);
    }
    if (record.isExpiredAt(at)) {
      return const PromoReservationRefused(PromoRefusalReason.expired);
    }

    // L'usage du compte est inséré par une instruction qui compte les
    // usages deja faits : la borne par compte ne peut pas etre depassee.
    final String usageId = _generator.generate().value;
    final Result usage = await _pool.execute(
      'INSERT INTO promo_code_usages (id, code, user_id, used_at) '
      'SELECT \$1, \$2, \$3, \$4 '
      'WHERE (SELECT count(*) FROM promo_code_usages '
      'WHERE code = \$2 AND user_id = \$3) < \$5',
      parameters: <Object?>[usageId, key, userId, at, record.maxUsesPerAccount],
    );
    if (usage.affectedRows == 0) {
      return const PromoReservationRefused(PromoRefusalReason.alreadyUsed);
    }

    // Le quota du code est decremente par une instruction conditionnelle :
    // deux reservations concurrentes ne peuvent pas le depasser.
    final Result counter = await _pool.execute(
      'UPDATE promo_codes SET uses = uses + 1 '
      'WHERE code = \$1 AND uses < max_uses',
      parameters: <Object?>[key],
    );
    if (counter.affectedRows == 0) {
      await _pool.execute(
        'DELETE FROM promo_code_usages WHERE id = \$1',
        parameters: <Object?>[usageId],
      );
      return const PromoReservationRefused(PromoRefusalReason.exhausted);
    }

    final PromoCodeRecord? updated = await findByCode(key);
    if (updated == null) {
      throw StateError('The promo code "$key" could not be read back.');
    }
    return PromoReservationGranted(updated);
  }

  @override
  Future<void> release({required String code, required String userId}) async {
    final String key = normalizePromoCode(code);
    // L'usage du compte est rendu d'abord : sans lui, le quota global
    // serait decremente pour une place qui n'existe pas.
    final Result usage = await _pool.execute(
      'DELETE FROM promo_code_usages WHERE id = ('
      'SELECT id FROM promo_code_usages WHERE code = \$1 AND user_id = \$2 '
      'ORDER BY used_at DESC, id DESC LIMIT 1)',
      parameters: <Object?>[key, userId],
    );
    if (usage.affectedRows == 0) return;
    await _pool.execute(
      'UPDATE promo_codes SET uses = uses - 1 WHERE code = \$1 AND uses > 0',
      parameters: <Object?>[key],
    );
  }

  /// Lit un code depuis une ligne.
  static PromoCodeRecord _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final PromoDiscountType type =
        PromoDiscountType.parse(columns['discount_type']! as String) ??
        PromoDiscountType.percent;
    return PromoCodeRecord(
      code: columns['code']! as String,
      discountType: type,
      value: (columns['value']! as num).toInt(),
      currency: columns['currency']! as String,
      maxUses: (columns['max_uses']! as num).toInt(),
      uses: (columns['uses']! as num).toInt(),
      maxUsesPerAccount: (columns['max_uses_per_account']! as num).toInt(),
      expiresAt: _readDate(columns['expires_at']),
      createdAt: _readDate(columns['created_at']),
    );
  }

  /// Lit un horodatage.
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
