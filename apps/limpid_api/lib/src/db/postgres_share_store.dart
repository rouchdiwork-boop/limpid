import 'package:postgres/postgres.dart';

import '../http/pagination.dart';
import 'share_store.dart';

/// L'implémentation Postgres du port [ShareStore].
///
/// Le jeton n'est jamais stocké en clair : la table ne porte que son
/// empreinte, ce qui fait qu'une fuite de la base ne donne aucun lien
/// utilisable.
final class PostgresShareStore implements ShareStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresShareStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'id, project_id, owner_id, token_hash, expires_at, is_revoked, '
      'created_at, revoked_at';

  @override
  Future<ShareRecord?> findById(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM project_shares WHERE id = \$1',
      parameters: <Object?>[id],
    );
    if (result.isEmpty) return null;
    return _readShare(result.first);
  }

  @override
  Future<SharePage> listByOwner({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE owner_id = \$1');

    if (decoded != null) {
      final DateTime createdAt = DateTime.parse(decoded.updatedAt).toUtc();
      where.write(' AND (created_at < \$2 OR (created_at = \$3 AND id > \$4))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final Result result = await _pool.execute(
      'SELECT $_columns FROM project_shares$where '
      'ORDER BY created_at DESC, id ASC LIMIT \$${parameters.length}',
      parameters: parameters,
    );
    final List<ShareRecord> rows = result
        .map(_readShare)
        .toList(growable: false);
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
    await _pool.execute(
      'INSERT INTO project_shares '
      '(id, project_id, owner_id, token_hash, expires_at, is_revoked, '
      'created_at, revoked_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8)',
      parameters: <Object?>[
        record.id,
        record.projectId,
        record.ownerId,
        record.tokenHash,
        record.expiresAt,
        record.isRevoked,
        record.createdAt,
        record.revokedAt,
      ],
    );
  }

  @override
  Future<void> update(ShareRecord record) async {
    await _pool.execute(
      'UPDATE project_shares SET expires_at = \$1, is_revoked = \$2, '
      'revoked_at = \$3 WHERE id = \$4',
      parameters: <Object?>[
        record.expiresAt,
        record.isRevoked,
        record.revokedAt,
        record.id,
      ],
    );
  }

  /// Le nombre de partages du compte [userId].
  Future<int> _count(String userId) async {
    final Result result = await _pool.execute(
      'SELECT count(*) AS total FROM project_shares WHERE owner_id = \$1',
      parameters: <Object?>[userId],
    );
    if (result.isEmpty) return 0;
    final Object? total = result.first.toColumnMap()['total'];
    return total is num ? total.toInt() : 0;
  }

  /// Lit un partage depuis une ligne.
  static ShareRecord _readShare(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return ShareRecord(
      id: columns['id']! as String,
      projectId: columns['project_id']! as String,
      ownerId: columns['owner_id']! as String,
      tokenHash: columns['token_hash']! as String,
      expiresAt: _readDate(columns['expires_at']),
      isRevoked: columns['is_revoked']! as bool,
      createdAt: _readDate(columns['created_at']),
      revokedAt: _readNullableDate(columns['revoked_at']),
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
