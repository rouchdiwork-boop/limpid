import 'package:postgres/postgres.dart';

import 'entitlement_store.dart';

/// L'implémentation Postgres du port [EntitlementStore].
///
/// L'octroi est idempotent : l'insertion ignore les conflits d'unicité,
/// et la ligne déjà écrite est relue. Un rejeu du même paiement ne crée
/// donc jamais un second droit.
final class PostgresEntitlementStore implements EntitlementStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresEntitlementStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'id, user_id, project_id, source, granted_at, created_at, '
      'amount_cents, currency, author_share, platform_share, '
      'author_amount_cents, platform_amount_cents, promo_code';

  @override
  Future<EntitlementRecord?> find({
    required String userId,
    required String projectId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM entitlements '
      'WHERE user_id = \$1 AND project_id = \$2',
      parameters: <Object?>[userId, projectId],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<EntitlementRecord?> findBySource(String source) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM entitlements WHERE source = \$1',
      parameters: <Object?>[source],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<EntitlementGrant> grant(EntitlementRecord record) async {
    final Result inserted = await _pool.execute(
      'INSERT INTO entitlements '
      '(id, user_id, project_id, source, granted_at, created_at, '
      'amount_cents, currency, author_share, platform_share, '
      'author_amount_cents, platform_amount_cents, promo_code) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, '
      '\$13) ON CONFLICT DO NOTHING',
      parameters: <Object?>[
        record.id,
        record.userId,
        record.projectId,
        record.source,
        record.grantedAt,
        record.createdAt,
        record.amountInCents,
        record.currency,
        record.authorShare,
        record.platformShare,
        record.authorAmountInCents,
        record.platformAmountInCents,
        record.promoCode,
      ],
    );
    if (inserted.affectedRows > 0) {
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
    final Result result = await _pool.execute(
      'SELECT $_columns FROM entitlements WHERE user_id = \$1 '
      'ORDER BY granted_at DESC, id ASC',
      parameters: <Object?>[userId],
    );
    return List<EntitlementRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  /// Lit un droit depuis une ligne.
  static EntitlementRecord _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return EntitlementRecord(
      id: columns['id']! as String,
      userId: columns['user_id']! as String,
      projectId: columns['project_id']! as String,
      source: columns['source']! as String,
      grantedAt: _readDate(columns['granted_at']),
      createdAt: _readDate(columns['created_at']),
      amountInCents: (columns['amount_cents']! as num).toInt(),
      currency: columns['currency']! as String,
      authorShare: (columns['author_share']! as num).toInt(),
      platformShare: (columns['platform_share']! as num).toInt(),
      authorAmountInCents: (columns['author_amount_cents']! as num).toInt(),
      platformAmountInCents: (columns['platform_amount_cents']! as num).toInt(),
      promoCode: columns['promo_code'] as String?,
    );
  }

  /// Lit un horodatage.
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
