import 'package:sqlite3/sqlite3.dart';

import 'entitlement_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [EntitlementStore].
///
/// L'octroi est idempotent : l'insertion ignore les conflits d'unicité, et
/// la ligne déjà écrite est relue. Un rejeu du même paiement ne crée donc
/// jamais un second droit.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteEntitlementStore implements EntitlementStore {
  /// Crée un magasin sur la base [database].
  const SqliteEntitlementStore(this._database);

  /// La base des droits.
  final SqliteDatabase _database;

  static const String _columns =
      'id, user_id, project_id, source, granted_at, created_at, '
      'amount_cents, currency, author_share, platform_share, '
      'author_amount_cents, platform_amount_cents, promo_code, bundle_id';

  @override
  Future<EntitlementRecord?> find({
    required String userId,
    required String projectId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM entitlements '
        'WHERE user_id = ? AND project_id = ?',
        <Object?>[userId, projectId],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<EntitlementRecord?> findBySource(String source) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM entitlements WHERE source = ?',
        <Object?>[source],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<EntitlementGrant> grant(EntitlementRecord record) async {
    final bool inserted = await _database.run(() {
      _database.connection.execute(
        'INSERT OR IGNORE INTO entitlements '
        '(id, user_id, project_id, source, granted_at, created_at, '
        'amount_cents, currency, author_share, platform_share, '
        'author_amount_cents, platform_amount_cents, promo_code, bundle_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.id,
          record.userId,
          record.projectId,
          record.source,
          SqliteValues.encodeTimestamp(record.grantedAt),
          SqliteValues.encodeTimestamp(record.createdAt),
          record.amountInCents,
          record.currency,
          record.authorShare,
          record.platformShare,
          record.authorAmountInCents,
          record.platformAmountInCents,
          record.promoCode,
          record.bundleId,
        ],
      );
      return _database.connection.updatedRows > 0;
    });
    if (inserted) {
      return EntitlementGrant(record: record, isNew: true);
    }
    // Le droit existait deja : il est relu, jamais recalcule.
    final EntitlementRecord? existing = await find(
      userId: record.userId,
      projectId: record.projectId,
    );
    if (existing != null) {
      return EntitlementGrant(record: existing, isNew: false);
    }
    final EntitlementRecord? bySource = await findBySource(record.source);
    if (bySource != null) {
      return EntitlementGrant(record: bySource, isNew: false);
    }
    throw StateError(
      'The entitlement "${record.id}" could not be stored nor read back.',
    );
  }

  @override
  Future<List<EntitlementRecord>> listByUser(String userId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM entitlements WHERE user_id = ? '
        'ORDER BY granted_at DESC, id ASC',
        <Object?>[userId],
      );
      return List<EntitlementRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  /// Lit un droit depuis une ligne.
  static EntitlementRecord _read(Row row) {
    return EntitlementRecord(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      projectId: row['project_id']! as String,
      source: row['source']! as String,
      grantedAt: SqliteValues.decodeTimestamp(row['granted_at']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      amountInCents: SqliteValues.decodeInt(row['amount_cents']),
      currency: row['currency']! as String,
      authorShare: SqliteValues.decodeInt(row['author_share']),
      platformShare: SqliteValues.decodeInt(row['platform_share']),
      authorAmountInCents: SqliteValues.decodeInt(row['author_amount_cents']),
      platformAmountInCents: SqliteValues.decodeInt(
        row['platform_amount_cents'],
      ),
      promoCode: row['promo_code'] as String?,
      bundleId: row['bundle_id'] as String?,
    );
  }
}
