import 'package:postgres/postgres.dart';

import 'bundle_record.dart';

/// L'implémentation Postgres du port [BundleStore].
///
/// Un bundle a un prix : l'écriture remplace le bundle précédent, et la
/// date de création est conservée.
///
/// Les livres du bundle sont stockés en JSON : leur **ordre** fait partie du
/// bundle, et une liste ordonnée est ce que la colonne porte.
final class PostgresBundleStore implements BundleStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresBundleStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'id, owner_id, title, description, project_ids, price_cents, currency, '
      'is_published, created_at';

  @override
  Future<BundleRecord?> findById(String bundleId) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM bundles WHERE id = \$1',
      parameters: <Object?>[bundleId],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<void> save(BundleRecord record) async {
    await _pool.execute(
      'INSERT INTO bundles '
      '(id, owner_id, title, description, project_ids, price_cents, currency, '
      'is_published, created_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9) '
      'ON CONFLICT (id) DO UPDATE SET '
      'owner_id = EXCLUDED.owner_id, '
      'title = EXCLUDED.title, '
      'description = EXCLUDED.description, '
      'project_ids = EXCLUDED.project_ids, '
      'price_cents = EXCLUDED.price_cents, '
      'currency = EXCLUDED.currency, '
      'is_published = EXCLUDED.is_published',
      parameters: <Object?>[
        record.id,
        record.ownerId,
        record.title,
        record.description,
        TypedValue(Type.jsonb, record.projectIds),
        record.priceInCents,
        record.currency,
        record.isPublished,
        record.createdAt,
      ],
    );
  }

  @override
  Future<List<BundleRecord>> listByOwner(String ownerId) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM bundles WHERE owner_id = \$1 '
      'ORDER BY created_at DESC, id ASC',
      parameters: <Object?>[ownerId],
    );
    return List<BundleRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  /// Lit un bundle depuis une ligne.
  static BundleRecord _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return BundleRecord(
      id: columns['id']! as String,
      ownerId: columns['owner_id']! as String,
      title: columns['title']! as String,
      description: columns['description']! as String,
      projectIds: decodeBundleProjectIds(columns['project_ids']),
      priceInCents: (columns['price_cents']! as num).toInt(),
      currency: columns['currency']! as String,
      isPublished: columns['is_published']! as bool,
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
