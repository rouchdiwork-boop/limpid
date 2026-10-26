import 'package:postgres/postgres.dart';

import 'book_sale_store.dart';

/// L'implémentation Postgres du port [BookSaleStore].
///
/// Un livre a un prix : l'écriture remplace la vente précédente, et la
/// date de création est conservée.
final class PostgresBookSaleStore implements BookSaleStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresBookSaleStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'project_id, owner_id, title, price_cents, currency, status, '
      'author_share, platform_share, artifact_key, created_at, updated_at, '
      'published_at';

  @override
  Future<BookSaleRecord?> findByProject(String projectId) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM book_sales WHERE project_id = \$1',
      parameters: <Object?>[projectId],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<void> save(BookSaleRecord record) async {
    await _pool.execute(
      'INSERT INTO book_sales '
      '(project_id, owner_id, title, price_cents, currency, status, '
      'author_share, platform_share, artifact_key, created_at, updated_at, '
      'published_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12) '
      'ON CONFLICT (project_id) DO UPDATE SET '
      'owner_id = EXCLUDED.owner_id, '
      'title = EXCLUDED.title, '
      'price_cents = EXCLUDED.price_cents, '
      'currency = EXCLUDED.currency, '
      'status = EXCLUDED.status, '
      'author_share = EXCLUDED.author_share, '
      'platform_share = EXCLUDED.platform_share, '
      'artifact_key = EXCLUDED.artifact_key, '
      'updated_at = EXCLUDED.updated_at, '
      'published_at = EXCLUDED.published_at',
      parameters: <Object?>[
        record.projectId,
        record.ownerId,
        record.title,
        record.priceInCents,
        record.currency,
        record.status.key,
        record.authorShare,
        record.platformShare,
        record.artifactKey,
        record.createdAt,
        record.updatedAt,
        record.publishedAt,
      ],
    );
  }

  @override
  Future<List<BookSaleRecord>> listByOwner(String ownerId) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM book_sales WHERE owner_id = \$1 '
      'ORDER BY updated_at DESC, project_id ASC',
      parameters: <Object?>[ownerId],
    );
    return List<BookSaleRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  /// Lit une vente depuis une ligne.
  static BookSaleRecord _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final BookSaleStatus status =
        BookSaleStatus.parse(columns['status']! as String) ??
        BookSaleStatus.draft;
    return BookSaleRecord(
      projectId: columns['project_id']! as String,
      ownerId: columns['owner_id']! as String,
      title: columns['title']! as String,
      priceInCents: (columns['price_cents']! as num).toInt(),
      currency: columns['currency']! as String,
      status: status,
      authorShare: (columns['author_share']! as num).toInt(),
      platformShare: (columns['platform_share']! as num).toInt(),
      artifactKey: columns['artifact_key'] as String?,
      createdAt: _readDate(columns['created_at']),
      updatedAt: _readDate(columns['updated_at']),
      publishedAt: _readNullableDate(columns['published_at']),
    );
  }

  /// Lit un horodatage.
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Lit un horodatage qui peut être absent.
  static DateTime? _readNullableDate(Object? value) {
    if (value == null) return null;
    return _readDate(value);
  }
}
