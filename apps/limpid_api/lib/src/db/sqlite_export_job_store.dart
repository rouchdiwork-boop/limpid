import 'package:sqlite3/sqlite3.dart';

import 'export_job_record.dart';
import 'export_job_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [ExportJobStore].
///
/// Les travaux vivent dans la table `exports`. Les horodatages sont
/// des entiers — microsecondes depuis l'epoch Unix (UTC) — comme dans
/// tout le dialecte SQLite.
final class SqliteExportJobStore implements ExportJobStore {
  /// Crée un magasin sur la base [database].
  const SqliteExportJobStore(this._database);

  /// La base des travaux.
  final SqliteDatabase _database;

  static const String _columns =
      'id, user_id, project_id, format, cover, status, artifact_key, error, '
      'error_code, created_at, started_at, finished_at, expires_at';

  @override
  Future<ExportJobRecord?> findById(String id) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM exports WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      return _read(result.first);
    });
  }

  @override
  Future<ExportJobRecord> insert(ExportJobRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO exports '
        '(id, user_id, project_id, format, cover, status, artifact_key, '
        'error, error_code, created_at, started_at, finished_at, expires_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.id,
          record.userId,
          record.projectId,
          record.format,
          record.cover,
          record.status.key,
          record.artifactKey,
          record.error,
          record.errorCode,
          SqliteValues.encodeTimestamp(record.createdAt),
          _encodeNullable(record.startedAt),
          _encodeNullable(record.finishedAt),
          _encodeNullable(record.expiresAt),
        ],
      );
    });
    return record;
  }

  @override
  Future<void> update(ExportJobRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE exports SET status = ?, artifact_key = ?, error = ?, '
        'error_code = ?, started_at = ?, finished_at = ?, expires_at = ? '
        'WHERE id = ?',
        <Object?>[
          record.status.key,
          record.artifactKey,
          record.error,
          record.errorCode,
          _encodeNullable(record.startedAt),
          _encodeNullable(record.finishedAt),
          _encodeNullable(record.expiresAt),
          record.id,
        ],
      );
    });
  }

  @override
  Future<List<ExportJobRecord>> listQueued({int limit = 50}) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM exports WHERE status = ? '
        'ORDER BY created_at ASC, id ASC LIMIT ?',
        <Object?>[ExportJobStatus.queued.key, limit],
      );
      return List<ExportJobRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  @override
  Future<List<ExportJobRecord>> listByUser({
    required String userId,
    int limit = 50,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM exports WHERE user_id = ? '
        'ORDER BY created_at DESC, id ASC LIMIT ?',
        <Object?>[userId, limit],
      );
      return List<ExportJobRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  @override
  Future<List<ExportJobRecord>> listExpired({
    required DateTime now,
    int limit = 50,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM exports '
        'WHERE status = ? AND expires_at IS NOT NULL AND expires_at <= ? '
        'ORDER BY expires_at ASC, id ASC LIMIT ?',
        <Object?>[
          ExportJobStatus.succeeded.key,
          SqliteValues.encodeTimestamp(now),
          limit,
        ],
      );
      return List<ExportJobRecord>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  /// Encode un horodatage qui peut être absent.
  static int? _encodeNullable(DateTime? value) {
    if (value == null) return null;
    return SqliteValues.encodeTimestamp(value);
  }

  /// Lit un travail depuis une ligne.
  static ExportJobRecord _read(Row row) {
    return ExportJobRecord(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      projectId: row['project_id']! as String,
      format: row['format']! as String,
      cover: row['cover']! as String,
      status:
          ExportJobStatus.fromKey(row['status']! as String) ??
          ExportJobStatus.failed,
      artifactKey: row['artifact_key'] as String?,
      error: row['error'] as String?,
      errorCode: row['error_code'] as String?,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      startedAt: SqliteValues.decodeNullableTimestamp(row['started_at']),
      finishedAt: SqliteValues.decodeNullableTimestamp(row['finished_at']),
      expiresAt: SqliteValues.decodeNullableTimestamp(row['expires_at']),
    );
  }
}
