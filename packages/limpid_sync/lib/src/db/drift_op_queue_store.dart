import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:limpid_sync/src/db/sync_database.dart';
import 'package:limpid_sync/src/queue/op_queue_store.dart';
import 'package:limpid_sync/src/queue/queued_op.dart';
import 'package:limpid_sync/src/transport/op_codec.dart';

/// An [OpQueueStore] persisting the queue in a SQLite database.
///
/// The database is opened by the application: this store only manipulates the
/// executor it is given, which keeps the package free of any Flutter
/// dependency.
final class DriftOpQueueStore implements OpQueueStore {
  /// Creates a store on top of [database].
  DriftOpQueueStore(this.database);

  /// The database holding the queue.
  final SyncDatabase database;

  @override
  Future<void> put(QueuedOp op) async {
    await database.opQueueRows.insertOnConflictUpdate(_toRow(op));
  }

  @override
  Future<void> putAll(Iterable<QueuedOp> ops) async {
    await database.transaction(() async {
      for (final op in ops) {
        await database.opQueueRows.insertOnConflictUpdate(_toRow(op));
      }
    });
  }

  @override
  Future<QueuedOp?> find(String operationKey) async {
    final query = database.select(database.opQueueRows)
      ..where((row) => row.operationKey.equals(operationKey));
    final entry = await query.getSingleOrNull();
    return entry == null ? null : _toOp(entry);
  }

  @override
  Future<List<QueuedOp>> all() async {
    final query = database.select(database.opQueueRows)
      ..orderBy(<OrderClauseGenerator<$OpQueueRowsTable>>[
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.lamport),
      ]);
    final entries = await query.get();
    return List<QueuedOp>.unmodifiable(entries.map(_toOp));
  }

  @override
  Future<void> remove(String operationKey) async {
    await (database.delete(
      database.opQueueRows,
    )..where((row) => row.operationKey.equals(operationKey))).go();
  }

  @override
  Future<void> removeAll(Iterable<String> operationKeys) async {
    final keys = operationKeys.toList(growable: false);
    if (keys.isEmpty) return;
    await (database.delete(
      database.opQueueRows,
    )..where((row) => row.operationKey.isIn(keys))).go();
  }

  @override
  Future<void> clear() async {
    await database.delete(database.opQueueRows).go();
  }

  @override
  Stream<List<QueuedOp>> watch() {
    final query = database.select(database.opQueueRows)
      ..orderBy(<OrderClauseGenerator<$OpQueueRowsTable>>[
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.lamport),
      ]);
    return query.watch().map(
      (entries) => List<QueuedOp>.unmodifiable(entries.map(_toOp)),
    );
  }

  OpQueueRowsCompanion _toRow(QueuedOp op) {
    return OpQueueRowsCompanion.insert(
      operationKey: op.operationKey,
      documentId: op.documentId,
      lamport: op.lamport,
      authorId: op.authorId,
      status: op.status.name,
      attempts: Value<int>(op.attempts),
      payload: jsonEncode(OpCodec.encode(op.operation)),
      createdAt: op.createdAt.millisecondsSinceEpoch,
      lastAttemptAt: Value<int?>(op.lastAttemptAt?.millisecondsSinceEpoch),
      nextAttemptAt: Value<int?>(op.nextAttemptAt?.millisecondsSinceEpoch),
      lastError: Value<String?>(op.lastError),
    );
  }

  QueuedOp _toOp(OpQueueEntry entry) {
    final decoded = jsonDecode(entry.payload);
    final operation = OpCodec.decode(decoded as Map<String, Object?>);
    return QueuedOp(
      operation: operation,
      status: OpQueueStatus.values.firstWhere(
        (status) => status.name == entry.status,
        orElse: () => OpQueueStatus.pending,
      ),
      attempts: entry.attempts,
      createdAt: DateTime.fromMillisecondsSinceEpoch(entry.createdAt),
      lastAttemptAt: _dateOf(entry.lastAttemptAt),
      nextAttemptAt: _dateOf(entry.nextAttemptAt),
      lastError: entry.lastError,
    );
  }

  DateTime? _dateOf(int? milliseconds) {
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
