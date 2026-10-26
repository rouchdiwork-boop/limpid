import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';

import '../http/pagination.dart';
import 'project_record.dart';
import 'project_store.dart';

/// The Postgres implementation of [ProjectStore].
///
/// Every query is parameterized: no value ever reaches the server through
/// string concatenation.
final class PostgresProjectStore implements ProjectStore {
  /// Creates a store on top of [pool].
  const PostgresProjectStore(this._pool);

  final Pool<Object?> _pool;

  static const String _columns =
      'id, owner_id, title, synopsis, status, language, order_key, '
      'is_public, created_at, updated_at, deleted_at';

  static const String _qualifiedColumns =
      'p.id, p.owner_id, p.title, p.synopsis, p.status, p.language, '
      'p.order_key, p.is_public, p.created_at, p.updated_at, p.deleted_at';

  @override
  Future<ProjectPage> list({
    required String userId,
    required int limit,
    required String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer()
      ..write(' WHERE p.deleted_at IS NULL AND (p.owner_id = \$1 OR EXISTS (')
      ..write(' SELECT 1 FROM project_members m ')
      ..write(' WHERE m.project_id = p.id AND m.user_id = \$1))');

    if (decoded != null) {
      parameters
        ..add(DateTime.parse(decoded.updatedAt))
        ..add(decoded.id);
      where.write(
        ' AND (p.updated_at < \$${parameters.length - 1} OR '
        '(p.updated_at = \$${parameters.length - 1} AND p.id > '
        '\$${parameters.length}))',
      );
    }

    parameters.add(limit + 1);
    final String limitParameter = '\$${parameters.length}';

    final Result result = await _pool.execute(
      'SELECT $_qualifiedColumns FROM projects p$where '
      'ORDER BY p.updated_at DESC, p.id ASC LIMIT $limitParameter',
      parameters: parameters,
    );

    final List<ProjectRecord> items = result
        .map((ResultRow row) => _readProject(row))
        .toList(growable: false);

    final bool hasMore = items.length > limit;
    final List<ProjectRecord> page = hasMore ? items.sublist(0, limit) : items;
    final String? nextCursor = hasMore && page.isNotEmpty
        ? PageCursor.encode(
            page.last.updatedAt.toUtc().toIso8601String(),
            page.last.id,
          )
        : null;

    final Result countResult = await _pool.execute(
      'SELECT count(*) AS total FROM projects p'
      ' WHERE p.deleted_at IS NULL AND (p.owner_id = \$1 OR EXISTS ('
      ' SELECT 1 FROM project_members m '
      ' WHERE m.project_id = p.id AND m.user_id = \$1))',
      parameters: <Object?>[userId],
    );
    final int total = countResult.isEmpty ? 0 : _readTotal(countResult.first);

    return ProjectPage(items: page, total: total, nextCursor: nextCursor);
  }

  @override
  Future<List<ProjectRecord>> listAll({required String userId}) async {
    final Result result = await _pool.execute(
      'SELECT $_qualifiedColumns FROM projects p '
      'WHERE p.owner_id = \$1 OR EXISTS ('
      ' SELECT 1 FROM project_members m '
      ' WHERE m.project_id = p.id AND m.user_id = \$1) '
      'ORDER BY p.created_at ASC, p.id ASC',
      parameters: <Object?>[userId],
    );
    return List<ProjectRecord>.unmodifiable(
      result.map((ResultRow row) => _readProject(row)).toList(growable: false),
    );
  }

  @override
  Future<ProjectAccess?> access({
    required String projectId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_qualifiedColumns, '
      " CASE WHEN p.owner_id = \$2 THEN 'owner' ELSE m.role END AS role "
      'FROM projects p '
      'LEFT JOIN project_members m ON m.project_id = p.id '
      'AND m.user_id = \$2 '
      'WHERE p.id = \$1 AND p.deleted_at IS NULL',
      parameters: <Object?>[projectId, userId],
    );
    if (result.isEmpty) return null;
    final Map<String, dynamic> row = result.first.toColumnMap();
    final Object? role = row['role'];
    if (role is! String) return null;
    final ProjectRole? parsed = _parseRole(role);
    if (parsed == null) return null;
    return ProjectAccess(project: _readProject(result.first), role: parsed);
  }

  @override
  Future<ProjectRecord?> findPublic({required String projectId}) async {
    final Result result = await _pool.execute(
      'SELECT $_qualifiedColumns FROM projects p '
      'WHERE p.id = \$1 AND p.status = \$2 AND p.is_public = TRUE '
      'AND p.deleted_at IS NULL',
      parameters: <Object?>[projectId, ManuscriptStatus.published.name],
    );
    if (result.isEmpty) return null;
    return _readProject(result.first);
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
    final Result result = await _pool.execute(
      'INSERT INTO projects '
      '(id, owner_id, title, synopsis, status, language, order_key, '
      'is_public, created_at, updated_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, FALSE, now(), now()) '
      'RETURNING $_columns',
      parameters: <Object?>[
        _newId(),
        ownerId,
        title,
        synopsis,
        status.name,
        language,
        orderKey,
      ],
    );
    return _readProject(result.first);
  }

  @override
  Future<ProjectRecord> update(ProjectRecord record) async {
    final Result result = await _pool.execute(
      'UPDATE projects SET title = \$2, synopsis = \$3, status = \$4, '
      'language = \$5, order_key = \$6, is_public = \$7, updated_at = now() '
      'WHERE id = \$1 AND deleted_at IS NULL RETURNING $_columns',
      parameters: <Object?>[
        record.id,
        record.title,
        record.synopsis,
        record.status.name,
        record.language,
        record.orderKey,
        record.isPublic,
      ],
    );
    if (result.isEmpty) {
      throw StateError('Project ${record.id} disappeared during the update.');
    }
    return _readProject(result.first);
  }

  @override
  Future<void> softDelete({required String projectId}) async {
    await _pool.execute(
      'UPDATE projects SET deleted_at = now(), updated_at = now() '
      'WHERE id = \$1 AND deleted_at IS NULL',
      parameters: <Object?>[projectId],
    );
  }

  static final UlidGenerator _ulid = UlidGenerator();

  static String _newId() => _ulid.generate().value;

  static ProjectRecord _readProject(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return ProjectRecord(
      id: columns['id']! as String,
      ownerId: columns['owner_id']! as String,
      title: columns['title']! as String,
      synopsis: (columns['synopsis'] as String?) ?? '',
      status: _parseStatus(columns['status'] as String?),
      language: (columns['language'] as String?) ?? 'fr-FR',
      orderKey: (columns['order_key'] as String?) ?? '5',
      isPublic: (columns['is_public'] as bool?) ?? false,
      createdAt: _readDate(columns['created_at']),
      updatedAt: _readDate(columns['updated_at']),
      deletedAt: columns['deleted_at'] == null
          ? null
          : _readDate(columns['deleted_at']),
    );
  }

  static int _readTotal(ResultRow row) {
    final Object? value = row.toColumnMap()['total'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
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
