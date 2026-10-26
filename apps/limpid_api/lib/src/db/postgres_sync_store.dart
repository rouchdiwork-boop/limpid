import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'sync_op_record.dart';
import 'sync_store.dart';

/// The Postgres implementation of [SyncStore].
///
/// The uniqueness constraint on `(doc_id, lamport, author_id)` carries the
/// idempotence of the push: an operation stored twice is detected by the
/// `ON CONFLICT DO NOTHING` clause and reported as a duplicate.
final class PostgresSyncStore implements SyncStore {
  /// Creates a store on top of [pool].
  const PostgresSyncStore(this._pool);

  final Pool<Object?> _pool;

  static const String _columns =
      'id, project_id, doc_id, lamport, author_id, type, payload, '
      'schema_version, created_at';

  @override
  Future<AppendResult> append({
    required String projectId,
    required List<SyncOpRecord> operations,
  }) async {
    if (operations.isEmpty) {
      final Result empty = await _pool.execute(
        'SELECT max(lamport) AS lamport FROM sync_ops WHERE project_id = \$1',
        parameters: <Object?>[projectId],
      );
      return AppendResult(
        accepted: const <SyncOpRecord>[],
        duplicated: const <SyncOpRecord>[],
        maxLamport: _readMaxLamport(empty),
      );
    }

    return _pool.runTx((Session session) async {
      final List<SyncOpRecord> accepted = <SyncOpRecord>[];
      final List<SyncOpRecord> duplicated = <SyncOpRecord>[];

      for (final SyncOpRecord operation in operations) {
        final Result result = await session.execute(
          'INSERT INTO sync_ops '
          '(id, project_id, doc_id, lamport, author_id, type, payload, '
          'schema_version) '
          'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8) '
          'ON CONFLICT (doc_id, lamport, author_id) DO NOTHING '
          'RETURNING $_columns',
          parameters: <Object?>[
            operation.opId,
            operation.projectId,
            operation.docId,
            operation.lamport,
            operation.authorId,
            operation.type,
            TypedValue(Type.jsonb, operation.payload),
            operation.schemaVersion,
          ],
        );
        if (result.isEmpty) {
          duplicated.add(operation);
        } else {
          accepted.add(_readOperation(result.first));
        }
      }

      final Result maxResult = await session.execute(
        'SELECT max(lamport) AS lamport FROM sync_ops WHERE project_id = \$1',
        parameters: <Object?>[projectId],
      );

      return AppendResult(
        accepted: accepted,
        duplicated: duplicated,
        maxLamport: _readMaxLamport(maxResult),
      );
    });
  }

  @override
  Future<List<SyncOpRecord>> since({
    required String projectId,
    required int lamport,
    required int limit,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM sync_ops '
      'WHERE project_id = \$1 AND lamport > \$2 '
      'ORDER BY lamport ASC, author_id ASC LIMIT \$3',
      parameters: <Object?>[projectId, lamport, limit],
    );
    return result.map(_readOperation).toList(growable: false);
  }

  @override
  Future<List<SyncOpRecord>> all({required String projectId}) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM sync_ops WHERE project_id = \$1 '
      'ORDER BY lamport ASC, author_id ASC',
      parameters: <Object?>[projectId],
    );
    return result.map(_readOperation).toList(growable: false);
  }

  @override
  Future<Set<String>> projectsOfDocument(String docId) async {
    final Result result = await _pool.execute(
      'SELECT DISTINCT project_id FROM sync_ops WHERE doc_id = \$1',
      parameters: <Object?>[docId],
    );
    return result
        .map((ResultRow row) => row.toColumnMap()['project_id']! as String)
        .toSet();
  }

  static int _readMaxLamport(Result result) {
    if (result.isEmpty) return 0;
    final Object? value = result.first.toColumnMap()['lamport'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static SyncOpRecord _readOperation(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final Object? payload = columns['payload'];
    return SyncOpRecord(
      opId: columns['id']! as String,
      projectId: columns['project_id']! as String,
      docId: columns['doc_id']! as String,
      lamport: _readInt(columns['lamport']),
      authorId: columns['author_id']! as String,
      type: columns['type']! as String,
      payload: _readPayload(payload),
      schemaVersion: _readInt(columns['schema_version']),
      createdAt: _readDate(columns['created_at']),
    );
  }

  static Map<String, dynamic> _readPayload(Object? payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is String) {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const <String, dynamic>{};
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
