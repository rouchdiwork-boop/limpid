import 'package:drift/drift.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The tables of the application that hold the data of the author.
///
/// The list follows `app_schema.dart`: the projects, the chapters, the
/// scenes, the index of the synchronised documents, the cursors of the
/// synchronisation, the preferences and the discussions of the review.
const List<String> localAuthorTables = <String>[
  'comments',
  'comment_threads',
  'scenes',
  'chapters',
  'document_index',
  'projects',
  'sync_cursors',
  'preferences',
  'project_members',
];

/// The tables of `limpid_sync` that hold the data of the author: the queue
/// of the operations waiting to be sent and the snapshots of the documents.
const List<String> syncAuthorTables = <String>[
  'op_queue_rows',
  'snapshot_rows',
];

/// The service that empties the local database of the device.
///
/// The wipe is the right to erasure on the device (D-19): once it ran, the
/// machine holds no manuscript, no scene, no snapshot of a document and no
/// operation waiting to be sent.
///
/// ## Complete and idempotent
///
/// The wipe empties **every** table that carries the data of the author —
/// the tables of the application and the tables of `limpid_sync` — and it is
/// idempotent: running it twice changes nothing and never fails. A table the
/// database does not hold is simply ignored: the list of the tables is
/// compared with the tables that really exist before anything is deleted.
final class LocalDataWiper {
  /// Creates a wiper on top of [database].
  const LocalDataWiper(this._database);

  /// The Drift database holding the tables.
  final SyncDatabase _database;

  /// Empties the local database of the device.
  ///
  /// The whole wipe runs in one transaction: the database is either emptied
  /// or untouched, never half emptied.
  Future<void> wipe() async {
    final Set<String> tables = await _existingTables();
    final List<String> wiped = <String>[
      ...localAuthorTables,
      ...syncAuthorTables,
    ].where(tables.contains).toList(growable: false);
    if (wiped.isEmpty) return;
    await _database.transaction(() async {
      for (final String table in wiped) {
        await _database.customStatement('DELETE FROM "$table"');
      }
    });
  }

  /// The tables the database really holds.
  Future<Set<String>> _existingTables() async {
    final List<QueryRow> rows = await _database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final Set<String> tables = <String>{};
    for (final QueryRow row in rows) {
      final Object? name = row.data['name'];
      if (name is String) tables.add(name);
    }
    return tables;
  }
}
