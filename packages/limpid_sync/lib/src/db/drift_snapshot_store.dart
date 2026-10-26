import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/db/sync_database.dart';
import 'package:limpid_sync/src/snapshot_store.dart';

/// A [SnapshotStore] persisting the snapshots in a SQLite database.
///
/// The database is opened by the application: this store only manipulates the
/// executor it is given, which keeps the package free of any Flutter
/// dependency.
final class DriftSnapshotStore implements SnapshotStore {
  /// Creates a store on top of [database].
  DriftSnapshotStore(this.database);

  /// The database holding the snapshots.
  final SyncDatabase database;

  @override
  Future<DocumentSnapshot?> read(DocumentId documentId) async {
    final query = database.select(database.snapshotRows)
      ..where((row) => row.documentId.equals(documentId.value));
    final entry = await query.getSingleOrNull();
    if (entry == null) return null;
    final decoded = jsonDecode(entry.payload);
    if (decoded is! Map<String, Object?>) return null;
    return DocumentSnapshot.fromJson(decoded);
  }

  @override
  Future<void> write(DocumentSnapshot snapshot) async {
    await database.snapshotRows.insertOnConflictUpdate(
      SnapshotRowsCompanion.insert(
        documentId: snapshot.documentId.value,
        since: snapshot.since,
        maxLamport: snapshot.maxLamport,
        payload: jsonEncode(snapshot.toJson()),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> remove(DocumentId documentId) async {
    await (database.delete(
      database.snapshotRows,
    )..where((row) => row.documentId.equals(documentId.value))).go();
  }
}
