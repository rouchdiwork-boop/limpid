import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../http/pagination.dart';
import 'project_record.dart';
import 'project_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// The SQLite implementation of [ProjectStore].
///
/// The adapter is the translation of the Postgres one: same queries, same
/// sort order, same isolation by owner and same soft delete. Every query is
/// parameterized: no value ever reaches the engine through string
/// concatenation.
///
/// The timestamps are stored as microseconds since the Unix epoch, the
/// convention of the SQLite dialect (see `SqliteValues`).
final class SqliteProjectStore implements ProjectStore {
  /// Creates a store on top of [database].
  const SqliteProjectStore(this._database);

  final SqliteDatabase _database;

  static const String _columns =
      'id, owner_id, title, synopsis, status, language, order_key, '
      'is_public, created_at, updated_at, deleted_at';

  static const String _qualifiedColumns =
      'p.id, p.owner_id, p.title, p.synopsis, p.status, p.language, '
      'p.order_key, p.is_public, p.created_at, p.updated_at, p.deleted_at';

  static final UlidGenerator _ulid = UlidGenerator();

  @override
  Future<ProjectPage> list({
    required String userId,
    required int limit,
    required String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[];
    final StringBuffer where = StringBuffer()
      ..write(' WHERE p.deleted_at IS NULL AND (p.owner_id = ? OR EXISTS (')
      ..write(' SELECT 1 FROM project_members m ')
      ..write(' WHERE m.project_id = p.id AND m.user_id = ?))');
    parameters
      ..add(userId)
      ..add(userId);

    if (decoded != null) {
      final int updatedAt = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(' AND (p.updated_at < ? OR (p.updated_at = ? AND p.id > ?))');
      parameters
        ..add(updatedAt)
        ..add(updatedAt)
        ..add(decoded.id);
    }

    parameters.add(limit + 1);

    final List<ProjectRecord> items = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_qualifiedColumns FROM projects p$where '
        'ORDER BY p.updated_at DESC, p.id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readProject).toList(growable: false);
    });

    final bool hasMore = items.length > limit;
    final List<ProjectRecord> page = hasMore ? items.sublist(0, limit) : items;
    final String? nextCursor = hasMore && page.isNotEmpty
        ? PageCursor.encode(
            page.last.updatedAt.toUtc().toIso8601String(),
            page.last.id,
          )
        : null;

    final int total = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT count(*) AS total FROM projects p'
        ' WHERE p.deleted_at IS NULL AND (p.owner_id = ? OR EXISTS ('
        ' SELECT 1 FROM project_members m '
        ' WHERE m.project_id = p.id AND m.user_id = ?))',
        <Object?>[userId, userId],
      );
      return result.isEmpty ? 0 : _readTotal(result.first);
    });

    return ProjectPage(items: page, total: total, nextCursor: nextCursor);
  }

  @override
  Future<List<ProjectRecord>> listAll({required String userId}) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_qualifiedColumns FROM projects p '
        'WHERE p.owner_id = ? OR EXISTS ('
        ' SELECT 1 FROM project_members m '
        ' WHERE m.project_id = p.id AND m.user_id = ?) '
        'ORDER BY p.created_at ASC, p.id ASC',
        <Object?>[userId, userId],
      );
      return List<ProjectRecord>.unmodifiable(
        result.map(_readProject).toList(growable: false),
      );
    });
  }

  @override
  Future<ProjectAccess?> access({
    required String projectId,
    required String userId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_qualifiedColumns, '
        " CASE WHEN p.owner_id = ? THEN 'owner' ELSE m.role END AS role "
        'FROM projects p '
        'LEFT JOIN project_members m ON m.project_id = p.id '
        'AND m.user_id = ? '
        'WHERE p.id = ? AND p.deleted_at IS NULL',
        <Object?>[userId, userId, projectId],
      );
      if (result.isEmpty) return null;
      final Object? role = result.first['role'];
      if (role is! String) return null;
      final ProjectRole? parsed = _parseRole(role);
      if (parsed == null) return null;
      return ProjectAccess(project: _readProject(result.first), role: parsed);
    });
  }

  @override
  Future<ProjectRecord?> findPublic({required String projectId}) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM projects p '
        'WHERE p.id = ? AND p.status = ? AND p.is_public = ? '
        'AND p.deleted_at IS NULL',
        <Object?>[
          projectId,
          ManuscriptStatus.published.name,
          SqliteValues.encodeBoolean(true),
        ],
      );
      return result.isEmpty ? null : _readProject(result.first);
    });
  }

  @override
  Future<ProjectRecord> create({
    required String ownerId,
    required String title,
    required String synopsis,
    required ManuscriptStatus status,
    required String language,
    required String orderKey,
  }) async {
    final String id = _ulid.generate().value;
    final DateTime now = DateTime.now().toUtc();
    final int timestamp = SqliteValues.encodeTimestamp(now);

    final ProjectRecord? stored = await _database.transaction(() {
      _database.connection.execute(
        'INSERT INTO projects '
        '(id, owner_id, title, synopsis, status, language, order_key, '
        'is_public, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          id,
          ownerId,
          title,
          synopsis,
          status.name,
          language,
          orderKey,
          SqliteValues.encodeBoolean(false),
          timestamp,
          timestamp,
        ],
      );
      return _readById(id);
    });

    if (stored == null) {
      throw StateError('Project $id could not be read back after creation.');
    }
    return stored;
  }

  @override
  Future<ProjectRecord> update(ProjectRecord record) async {
    final int timestamp = SqliteValues.encodeTimestamp(DateTime.now().toUtc());

    final ProjectRecord? stored = await _database.transaction(() {
      _database.connection.execute(
        'UPDATE projects SET title = ?, synopsis = ?, status = ?, '
        'language = ?, order_key = ?, is_public = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        <Object?>[
          record.title,
          record.synopsis,
          record.status.name,
          record.language,
          record.orderKey,
          SqliteValues.encodeBoolean(record.isPublic),
          timestamp,
          record.id,
        ],
      );
      if (_database.connection.updatedRows == 0) return null;
      return _readById(record.id);
    });

    if (stored == null) {
      throw StateError('Project ${record.id} disappeared during the update.');
    }
    return stored;
  }

  @override
  Future<void> softDelete({required String projectId}) async {
    final int timestamp = SqliteValues.encodeTimestamp(DateTime.now().toUtc());
    await _database.run(() {
      _database.connection.execute(
        'UPDATE projects SET deleted_at = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        <Object?>[timestamp, timestamp, projectId],
      );
    });
  }

  /// Reads a project by its identifier, on the current connection.
  ///
  /// The caller must hold the queue of the database: the method is called
  /// from inside a transaction or from inside a queued action.
  ProjectRecord? _readById(String id) {
    final ResultSet result = _database.connection.select(
      'SELECT $_columns FROM projects WHERE id = ?',
      <Object?>[id],
    );
    return result.isEmpty ? null : _readProject(result.first);
  }

  static ProjectRecord _readProject(Row row) {
    return ProjectRecord(
      id: row['id']! as String,
      ownerId: row['owner_id']! as String,
      title: row['title']! as String,
      synopsis: (row['synopsis'] as String?) ?? '',
      status: _parseStatus(row['status'] as String?),
      language: (row['language'] as String?) ?? 'fr-FR',
      orderKey: (row['order_key'] as String?) ?? '5',
      isPublic: SqliteValues.decodeBoolean(row['is_public']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
      deletedAt: SqliteValues.decodeNullableTimestamp(row['deleted_at']),
    );
  }

  static int _readTotal(Row row) {
    final Object? value = row['total'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static ManuscriptStatus _parseStatus(String? raw) {
    for (final ManuscriptStatus status in ManuscriptStatus.values) {
      if (status.name == raw) return status;
    }
    return ManuscriptStatus.draft;
  }

  static ProjectRole? _parseRole(String raw) {
    for (final ProjectRole role in ProjectRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}
