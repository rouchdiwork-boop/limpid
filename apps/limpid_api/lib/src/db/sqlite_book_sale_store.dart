import 'package:sqlite3/sqlite3.dart';

import 'book_sale_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [BookSaleStore].
///
/// L'adaptateur est la traduction du port Postgres : mêmes requêtes, même
/// tri, même unicité du prix par livre. Chaque requête est paramétrée :
/// aucune valeur n'atteint jamais le moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteBookSaleStore implements BookSaleStore {
  /// Crée un magasin sur la base [database].
  const SqliteBookSaleStore(this._database);

  /// La base des ventes.
  final SqliteDatabase _database;

  static const String _columns =
      'project_id, owner_id, title, price_cents, currency, status, '
      'author_share, platform_share, artifact_key, created_at, updated_at, '
      'published_at';

  @override
  Future<BookSaleRecord?> findByProject(String projectId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM book_sales WHERE project_id = ?',
        <Object?>[projectId],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<void> save(BookSaleRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO book_sales '
        '(project_id, owner_id, title, price_cents, currency, status, '
        'author_share, platform_share, artifact_key, created_at, updated_at, '
        'published_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(project_id) DO UPDATE SET '
        'owner_id = excluded.owner_id, '
        'title = excluded.title, '
        'price_cents = excluded.price_cents, '
        'currency = excluded.currency, '
        'status = excluded.status, '
        'author_share = excluded.author_share, '
        'platform_share = excluded.platform_share, '
        'artifact_key = excluded.artifact_key, '
        'updated_at = excluded.updated_at, '
        'published_at = excluded.published_at',
        <Object?>[
          record.projectId,
          record.ownerId,
          record.title,
          record.priceInCents,
          record.currency,
          record.status.key,
          record.authorShare,
          record.platformShare,
          record.artifactKey,
          SqliteValues.encodeTimestamp(record.createdAt),
          SqliteValues.encodeTimestamp(record.updatedAt),
          _encodeNullable(record.publishedAt),
        ],
      );
    });
  }

  @override
  Future<List<BookSaleRecord>> listByOwner(String ownerId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM book_sales WHERE owner_id = ? '
        'ORDER BY updated_at DESC, project_id ASC',
        <Object?>[ownerId],
      );
      return List<BookSaleRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  /// Encode un horodatage qui peut être absent.
  static int? _encodeNullable(DateTime? value) {
    if (value == null) return null;
    return SqliteValues.encodeTimestamp(value);
  }

  /// Lit une vente depuis une ligne.
  static BookSaleRecord _read(Row row) {
    final BookSaleStatus status =
        BookSaleStatus.parse(row['status']! as String) ?? BookSaleStatus.draft;
    return BookSaleRecord(
      projectId: row['project_id']! as String,
      ownerId: row['owner_id']! as String,
      title: row['title']! as String,
      priceInCents: SqliteValues.decodeInt(row['price_cents']),
      currency: row['currency']! as String,
      status: status,
      authorShare: SqliteValues.decodeInt(row['author_share']),
      platformShare: SqliteValues.decodeInt(row['platform_share']),
      artifactKey: row['artifact_key'] as String?,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
      publishedAt: SqliteValues.decodeNullableTimestamp(row['published_at']),
    );
  }
}
