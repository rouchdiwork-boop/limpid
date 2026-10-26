import 'package:postgres/postgres.dart';

import 'export_job_record.dart';
import 'export_job_store.dart';

/// L'implémentation Postgres du port [ExportJobStore].
///
/// Les travaux vivent dans la table `exports`. La file du worker est
/// lue par l'index `(status, created_at)` : le worker prend le travail le
/// plus ancien sans balayer la table.
final class PostgresExportJobStore implements ExportJobStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresExportJobStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'id, user_id, project_id, format, cover, status, artifact_key, error, '
      'error_code, created_at, started_at, finished_at, expires_at';

  @override
  Future<ExportJobRecord?> findById(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM exports WHERE id = \$1',
      parameters: <Object?>[id],
    );
    if (result.isEmpty) return null;
    return _read(result.first);
  }

  @override
  Future<ExportJobRecord> insert(ExportJobRecord record) async {
    await _pool.execute(
      'INSERT INTO exports '
      '(id, user_id, project_id, format, cover, status, artifact_key, error, '
      'error_code, created_at, started_at, finished_at, expires_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, '
      '\$12, \$13)',
      parameters: <Object?>[
        record.id,
        record.userId,
        record.projectId,
        record.format,
        record.cover,
        record.status.key,
        record.artifactKey,
        record.error,
        record.errorCode,
        record.createdAt,
        record.startedAt,
        record.finishedAt,
        record.expiresAt,
      ],
    );
    return record;
  }

  @override
  Future<void> update(ExportJobRecord record) async {
    await _pool.execute(
      'UPDATE exports SET status = \$1, artifact_key = \$2, error = \$3, '
      'error_code = \$4, started_at = \$5, finished_at = \$6, expires_at = \$7 '
      'WHERE id = \$8',
      parameters: <Object?>[
        record.status.key,
        record.artifactKey,
        record.error,
        record.errorCode,
        record.startedAt,
        record.finishedAt,
        record.expiresAt,
        record.id,
      ],
    );
  }

  @override
  Future<List<ExportJobRecord>> listQueued({int limit = 50}) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM exports WHERE status = \$1 '
      'ORDER BY created_at ASC, id ASC LIMIT \$2',
      parameters: <Object?>[ExportJobStatus.queued.key, limit],
    );
    return List<ExportJobRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  @override
  Future<List<ExportJobRecord>> listByUser({
    required String userId,
    int limit = 50,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM exports WHERE user_id = \$1 '
      'ORDER BY created_at DESC, id ASC LIMIT \$2',
      parameters: <Object?>[userId, limit],
    );
    return List<ExportJobRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  @override
  Future<List<ExportJobRecord>> listExpired({
    required DateTime now,
    int limit = 50,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM exports '
      'WHERE status = \$1 AND expires_at IS NOT NULL AND expires_at <= \$2 '
      'ORDER BY expires_at ASC, id ASC LIMIT \$3',
      parameters: <Object?>[ExportJobStatus.succeeded.key, now.toUtc(), limit],
    );
    return List<ExportJobRecord>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  /// Lit un travail depuis une ligne.
  static ExportJobRecord _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return ExportJobRecord(
      id: columns['id']! as String,
      userId: columns['user_id']! as String,
      projectId: columns['project_id']! as String,
      format: columns['format']! as String,
      cover: columns['cover']! as String,
      status:
          ExportJobStatus.fromKey(columns['status']! as String) ??
          ExportJobStatus.failed,
      artifactKey: columns['artifact_key'] as String?,
      error: columns['error'] as String?,
      errorCode: columns['error_code'] as String?,
      createdAt: _readDate(columns['created_at']),
      startedAt: _readNullableDate(columns['started_at']),
      finishedAt: _readNullableDate(columns['finished_at']),
      expiresAt: _readNullableDate(columns['expires_at']),
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
