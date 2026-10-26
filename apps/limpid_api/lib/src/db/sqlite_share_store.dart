import 'package:sqlite3/sqlite3.dart';

import '../http/pagination.dart';
import 'share_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [ShareStore].
///
/// L'adaptateur est la traduction du port Postgres : mêmes requêtes, même
/// ordre de tri, même isolement par propriétaire. Chaque requête est
/// paramétrée : aucune valeur n'atteint jamais le moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteShareStore implements ShareStore {
  /// Crée un magasin sur la base [database].
  const SqliteShareStore(this._database);

  /// La base des partages.
  final SqliteDatabase _database;

  static const String _columns =
      'id, project_id, owner_id, token_hash, expires_at, is_revoked, '
      'created_at, revoked_at';

  @override
  Future<ShareRecord?> findById(String id) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM project_shares WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      return _readShare(result.first);
    });
  }

  @override
  Future<SharePage> listByOwner({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE owner_id = ?');

    if (decoded != null) {
      final int createdAt = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(' AND (created_at < ? OR (created_at = ? AND id > ?))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final List<ShareRecord> rows = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM project_shares$where '
        'ORDER BY created_at DESC, id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readShare).toList(growable: false);
    });

    final bool hasMore = rows.length > limit;
    final List<ShareRecord> items = hasMore ? rows.sublist(0, limit) : rows;
    final int total = await _count(userId);
    return SharePage(
      items: List<ShareRecord>.unmodifiable(items),
      total: total,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              items.last.createdAt.toUtc().toIso8601String(),
              items.last.id,
            )
          : null,
    );
  }

  @override
  Future<void> insert(ShareRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO project_shares '
        '(id, project_id, owner_id, token_hash, expires_at, is_revoked, '
        'created_at, revoked_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.id,
          record.projectId,
          record.ownerId,
          record.tokenHash,
          SqliteValues.encodeTimestamp(record.expiresAt),
          SqliteValues.encodeBoolean(record.isRevoked),
          SqliteValues.encodeTimestamp(record.createdAt),
          _encodeNullable(record.revokedAt),
        ],
      );
    });
  }

  @override
  Future<void> update(ShareRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE project_shares SET expires_at = ?, is_revoked = ?, '
        'revoked_at = ? WHERE id = ?',
        <Object?>[
          SqliteValues.encodeTimestamp(record.expiresAt),
          SqliteValues.encodeBoolean(record.isRevoked),
          _encodeNullable(record.revokedAt),
          record.id,
        ],
      );
    });
  }

  /// Le nombre de partages du compte [userId].
  Future<int> _count(String userId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT count(*) AS total FROM project_shares WHERE owner_id = ?',
        <Object?>[userId],
      );
      if (result.isEmpty) return 0;
      return SqliteValues.decodeInt(result.first['total']);
    });
  }

  /// Encode un horodatage qui peut être absent.
  static int? _encodeNullable(DateTime? value) {
    if (value == null) return null;
    return SqliteValues.encodeTimestamp(value);
  }

  /// Lit un partage depuis une ligne.
  static ShareRecord _readShare(Row row) {
    return ShareRecord(
      id: row['id']! as String,
      projectId: row['project_id']! as String,
      ownerId: row['owner_id']! as String,
      tokenHash: row['token_hash']! as String,
      expiresAt: SqliteValues.decodeTimestamp(row['expires_at']),
      isRevoked: SqliteValues.decodeBoolean(row['is_revoked']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      revokedAt: SqliteValues.decodeNullableTimestamp(row['revoked_at']),
    );
  }
}
