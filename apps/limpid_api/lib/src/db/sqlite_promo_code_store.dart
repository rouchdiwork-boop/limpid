import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'promo_code_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [PromoCodeStore].
///
/// La réservation est atomique : l'usage du compte est inséré par une seule
/// instruction qui compte les usages déjà faits, et le quota du code est
/// décrémenté par une instruction conditionnelle. Deux réservations
/// concurrentes ne peuvent pas dépasser le quota, et un compte ne peut pas
/// utiliser un code plus de fois qu'il n'y a droit.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqlitePromoCodeStore implements PromoCodeStore {
  /// Crée un magasin sur la base [database].
  SqlitePromoCodeStore(this._database, {UlidGenerator? generator})
    : _generator = generator ?? UlidGenerator();

  /// La base des codes promo.
  final SqliteDatabase _database;

  final UlidGenerator _generator;

  static const String _columns =
      'code, discount_type, value, currency, max_uses, uses, '
      'max_uses_per_account, expires_at, created_at';

  @override
  Future<PromoCodeRecord?> findByCode(String code) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM promo_codes WHERE code = ?',
        <Object?>[normalizePromoCode(code)],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<void> save(PromoCodeRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO promo_codes '
        '(code, discount_type, value, currency, max_uses, uses, '
        'max_uses_per_account, expires_at, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(code) DO UPDATE SET '
        'discount_type = excluded.discount_type, '
        'value = excluded.value, '
        'currency = excluded.currency, '
        'max_uses = excluded.max_uses, '
        'uses = excluded.uses, '
        'max_uses_per_account = excluded.max_uses_per_account, '
        'expires_at = excluded.expires_at',
        <Object?>[
          normalizePromoCode(record.code),
          record.discountType.key,
          record.value,
          record.currency,
          record.maxUses,
          record.uses,
          record.maxUsesPerAccount,
          SqliteValues.encodeTimestamp(record.expiresAt),
          SqliteValues.encodeTimestamp(record.createdAt),
        ],
      );
    });
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
    final bool recorded = await _database.run(() {
      _database.connection.execute(
        'INSERT INTO promo_code_usages (id, code, user_id, used_at) '
        'SELECT ?, ?, ?, ? '
        'WHERE (SELECT count(*) FROM promo_code_usages '
        'WHERE code = ? AND user_id = ?) < ?',
        <Object?>[
          usageId,
          key,
          userId,
          SqliteValues.encodeTimestamp(at),
          key,
          userId,
          record.maxUsesPerAccount,
        ],
      );
      return _database.connection.updatedRows > 0;
    });
    if (!recorded) {
      return const PromoReservationRefused(PromoRefusalReason.alreadyUsed);
    }

    // Le quota du code est decremente par une instruction conditionnelle :
    // deux reservations concurrentes ne peuvent pas le depasser.
    final bool counted = await _database.run(() {
      _database.connection.execute(
        'UPDATE promo_codes SET uses = uses + 1 '
        'WHERE code = ? AND uses < max_uses',
        <Object?>[key],
      );
      return _database.connection.updatedRows > 0;
    });
    if (!counted) {
      await _database.run(() {
        _database.connection.execute(
          'DELETE FROM promo_code_usages WHERE id = ?',
          <Object?>[usageId],
        );
      });
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
    await _database.run(() {
      // L'usage du compte est rendu d'abord : sans lui, le quota global
      // serait decremente pour une place qui n'existe pas.
      _database.connection.execute(
        'DELETE FROM promo_code_usages WHERE id = ('
        'SELECT id FROM promo_code_usages WHERE code = ? AND user_id = ? '
        'ORDER BY used_at DESC, id DESC LIMIT 1)',
        <Object?>[key, userId],
      );
      final bool released = _database.connection.updatedRows > 0;
      if (!released) return;
      _database.connection.execute(
        'UPDATE promo_codes SET uses = uses - 1 WHERE code = ? AND uses > 0',
        <Object?>[key],
      );
    });
  }

  /// Lit un code depuis une ligne.
  static PromoCodeRecord _read(Row row) {
    final PromoDiscountType type =
        PromoDiscountType.parse(row['discount_type']! as String) ??
        PromoDiscountType.percent;
    return PromoCodeRecord(
      code: row['code']! as String,
      discountType: type,
      value: SqliteValues.decodeInt(row['value']),
      currency: row['currency']! as String,
      maxUses: SqliteValues.decodeInt(row['max_uses']),
      uses: SqliteValues.decodeInt(row['uses']),
      maxUsesPerAccount: SqliteValues.decodeInt(row['max_uses_per_account']),
      expiresAt: SqliteValues.decodeTimestamp(row['expires_at']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }
}
