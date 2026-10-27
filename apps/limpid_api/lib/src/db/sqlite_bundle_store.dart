import 'package:sqlite3/sqlite3.dart';

import 'bundle_record.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [BundleStore].
///
/// L'adaptateur est la traduction du port Postgres : mêmes requêtes, même
/// tri, même unicité du prix par bundle. Chaque requête est paramétrée :
/// aucune valeur n'atteint jamais le moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteBundleStore implements BundleStore {
  /// Crée un magasin sur la base [database].
  const SqliteBundleStore(this._database);

  /// La base des bundles.
  final SqliteDatabase _database;

  static const String _columns =
      'id, owner_id, title, description, project_ids, price_cents, currency, '
      'is_published, created_at';

  @override
  Future<BundleRecord?> findById(String bundleId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM bundles WHERE id = ?',
        <Object?>[bundleId],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<void> save(BundleRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO bundles '
        '(id, owner_id, title, description, project_ids, price_cents, '
        'currency, is_published, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET '
        'owner_id = excluded.owner_id, '
        'title = excluded.title, '
        'description = excluded.description, '
        'project_ids = excluded.project_ids, '
        'price_cents = excluded.price_cents, '
        'currency = excluded.currency, '
        'is_published = excluded.is_published',
        <Object?>[
          record.id,
          record.ownerId,
          record.title,
          record.description,
          encodeBundleProjectIds(record.projectIds),
          record.priceInCents,
          record.currency,
          SqliteValues.encodeBoolean(record.isPublished),
          SqliteValues.encodeTimestamp(record.createdAt),
        ],
      );
    });
  }

  @override
  Future<List<BundleRecord>> listByOwner(String ownerId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM bundles WHERE owner_id = ? '
        'ORDER BY created_at DESC, id ASC',
        <Object?>[ownerId],
      );
      return List<BundleRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  /// Lit un bundle depuis une ligne.
  static BundleRecord _read(Row row) {
    return BundleRecord(
      id: row['id']! as String,
      ownerId: row['owner_id']! as String,
      title: row['title']! as String,
      description: row['description']! as String,
      projectIds: decodeBundleProjectIds(row['project_ids']),
      priceInCents: SqliteValues.decodeInt(row['price_cents']),
      currency: row['currency']! as String,
      isPublished: SqliteValues.decodeBoolean(row['is_published']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }
}
