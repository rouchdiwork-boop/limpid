import 'package:sqlite3/sqlite3.dart';

import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'sync_op_record.dart';
import 'sync_store.dart';

/// The SQLite implementation of [SyncStore].
///
/// The uniqueness constraint on `(doc_id, lamport, author_id)` carries the
/// idempotence of the push: an operation stored twice is detected by the
/// `ON CONFLICT DO NOTHING` clause and reported as a duplicate.
///
/// The whole batch is applied in a single transaction, exactly like the
/// Postgres implementation, so a push is either fully stored or not stored
/// at all.
final class SqliteSyncStore implements SyncStore {
  /// Creates a store on top of [database].
  const SqliteSyncStore(this._database);

  final SqliteDatabase _database;

  static const String _columns =
      'id, project_id, doc_id, lamport, author_id, type, payload, '
      'schema_version, created_at';

  @override
  Future<AppendResult> append({
    required String projectId,
    required List<SyncOpRecord> operations,
  }) async {
    if (operations.isEmpty) {
      return AppendResult(
        accepted: const <SyncOpRecord>[],
        duplicated: const <SyncOpRecord>[],
        maxLamport: await _maxLamport(projectId),
      );
    }

    return _database.transaction(() {
      final List<SyncOpRecord> accepted = <SyncOpRecord>[];
      final List<SyncOpRecord> duplicated = <SyncOpRecord>[];

      for (final SyncOpRecord operation in operations) {
        final bool stored = _insert(operation);
        if (!stored) {
          duplicated.add(operation);
          continue;
        }
        final SyncOpRecord? read = _findById(operation.opId);
        if (read == null) {
          throw StateError(
            'Operation ${operation.opId} could not be read back after '
            'insertion.',
          );
        }
        accepted.add(read);
      }

      return AppendResult(
        accepted: accepted,
        duplicated: duplicated,
        maxLamport: _maxLamportSync(projectId),
      );
    });
  }

  @override
  Future<List<SyncOpRecord>> since({
    required String projectId,
    required int lamport,
    required int limit,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM sync_ops '
        'WHERE project_id = ? AND lamport > ? '
        'ORDER BY lamport ASC, author_id ASC LIMIT ?',
        <Object?>[projectId, lamport, limit],
      );
      return result.map(_readOperation).toList(growable: false);
    });
  }

  @override
  Future<List<SyncOpRecord>> all({required String projectId}) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM sync_ops WHERE project_id = ? '
        'ORDER BY lamport ASC, author_id ASC',
        <Object?>[projectId],
      );
      return result.map(_readOperation).toList(growable: false);
    });
  }

  @override
  Future<Set<String>> projectsOfDocument(String docId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT DISTINCT project_id FROM sync_ops WHERE doc_id = ?',
        <Object?>[docId],
      );
      return result.map((Row row) => row['project_id']! as String).toSet();
    });
  }

  /// Inserts an operation, telling whether it was actually stored.
  ///
  /// The `ON CONFLICT DO NOTHING` clause leaves the row untouched when the
  /// operation is already known; the number of rows touched by the statement
  /// then tells the two cases apart.
  bool _insert(SyncOpRecord operation) {
    _database.connection.execute(
      'INSERT INTO sync_ops '
      '(id, project_id, doc_id, lamport, author_id, type, payload, '
      'schema_version, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (doc_id, lamport, author_id) DO NOTHING',
      <Object?>[
        operation.opId,
        operation.projectId,
        operation.docId,
        operation.lamport,
        operation.authorId,
        operation.type,
        SqliteValues.encodeJson(operation.payload),
        operation.schemaVersion,
        SqliteValues.encodeTimestamp(operation.createdAt),
      ],
    );
    return _database.connection.updatedRows > 0;
  }

  SyncOpRecord? _findById(String id) {
    final ResultSet result = _database.connection.select(
      'SELECT $_columns FROM sync_ops WHERE id = ?',
      <Object?>[id],
    );
    return result.isEmpty ? null : _readOperation(result.first);
  }

  Future<int> _maxLamport(String projectId) {
    return _database.run(() => _maxLamportSync(projectId));
  }

  int _maxLamportSync(String projectId) {
    final ResultSet result = _database.connection.select(
      'SELECT max(lamport) AS lamport FROM sync_ops WHERE project_id = ?',
      <Object?>[projectId],
    );
    if (result.isEmpty) return 0;
    return SqliteValues.decodeInt(result.first['lamport']);
  }

  static SyncOpRecord _readOperation(Row row) {
    return SyncOpRecord(
      opId: row['id']! as String,
      projectId: row['project_id']! as String,
      docId: row['doc_id']! as String,
      lamport: SqliteValues.decodeInt(row['lamport']),
      authorId: row['author_id']! as String,
      type: row['type']! as String,
      payload: SqliteValues.decodeJson(row['payload']),
      schemaVersion: SqliteValues.decodeInt(row['schema_version']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }
}
