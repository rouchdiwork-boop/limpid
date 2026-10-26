import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/data/app_schema.dart';
import 'package:limpid_app/src/data/local_data_wiper.dart';
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/project_membership_store.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The name of the local database file, without its extension.
const String localDatabaseName = 'limpid';

/// The message shown when the local database cannot be opened.
///
/// The web build is the usual cause: Drift needs a WebAssembly backend, and
/// the application cannot produce one at runtime.
const String localDatabaseUnavailableMessage =
    'The local database could not be opened. The web build of Limpid needs '
    'the SQLite WebAssembly module (web/sqlite3.wasm) and the Drift worker '
    '(web/drift_worker.js), served next to index.html.';

/// The local database of the application.
///
/// It holds the state the interface displays — the projects, the chapters,
/// the scenes — the CRDT documents of the scenes, and the queue of the
/// operations waiting to reach the server.
///
/// ## One file, one connection
///
/// The application schema and the schema of `limpid_sync` (the queue and the
/// snapshots) live in the **same** SQLite file, opened through a single
/// Drift connection. Two connections on the same file would fight over the
/// write lock; one connection keeps the writes of the interface and the
/// writes of the synchronisation in the same transaction.
///
/// ## The web
///
/// Drift needs a WebAssembly backend on the web: `sqlite3.wasm` and
/// `drift_worker.js` must be served next to `index.html`. When they are
/// missing, the opening fails and the application reports a
/// [LocalDatabaseUnavailableException] that names the two missing files.
/// There is deliberately **no** in-memory fallback on the web: an in-memory
/// database would silently lose the manuscript of the author the moment the
/// tab is closed, which is exactly the promise the product must keep.
final class AppDatabase {
  AppDatabase._(this.sync);

  /// Creates a database on top of [executor].
  ///
  /// The schema is **not** created: call [openWith] to get a ready database.
  AppDatabase.forExecutor(QueryExecutor executor)
    : sync = SyncDatabase(executor);

  /// The Drift database of the synchronisation: the queue and the snapshots.
  final SyncDatabase sync;

  /// The state the interface displays.
  late final ManuscriptStore manuscripts = ManuscriptStore(sync);

  /// The durable queue of the operations waiting to be sent.
  late final DriftOpQueueStore queueStore = DriftOpQueueStore(sync);

  /// The persistence of the CRDT documents of the scenes.
  late final DriftSnapshotStore snapshots = DriftSnapshotStore(sync);

  /// The queue of the operations, with the retry policy of `limpid_sync`.
  late final OpQueue queue = OpQueue(store: queueStore);

  /// The service that empties the local data of the author (RGPD).
  ///
  /// The wipe is the right to erasure on the device: once it ran, the
  /// machine holds no manuscript, no scene, no snapshot and no pending
  /// operation of the author.
  late final LocalDataWiper wiper = LocalDataWiper(sync);

  /// The memberships of the projects, for the reads scoped to the author.
  late final ProjectMembershipStore memberships = ProjectMembershipStore(sync);

  /// Opens the local database of the device.
  ///
  /// On mobile and on desktop the file lives in the documents directory of
  /// the application and the connection is hosted by a background isolate:
  /// the persistence never blocks the UI. On the web the connection needs
  /// the WebAssembly backend, and an explicit error is raised when it is
  /// missing.
  static Future<AppDatabase> open({String name = localDatabaseName}) async {
    final AppDatabase database = AppDatabase._(SyncDatabase(_connection(name)));
    try {
      await database._createSchema();
    } on Object catch (error) {
      await database.close();
      throw LocalDatabaseUnavailableException(
        localDatabaseUnavailableMessage,
        cause: error,
      );
    }
    return database;
  }

  /// Opens a local database on top of [executor].
  ///
  /// The tests use it with an in-memory executor.
  static Future<AppDatabase> openWith(QueryExecutor executor) async {
    final AppDatabase database = AppDatabase.forExecutor(executor);
    await database._createSchema();
    return database;
  }

  /// Closes the database and releases the resources of the connection.
  Future<void> close() => sync.close();

  /// Opens the connection of the database on the current platform.
  static DatabaseConnection _connection(String name) {
    if (kIsWeb) {
      return driftDatabase(
        name: name,
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );
    }
    return driftDatabase(
      name: name,
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    );
  }

  /// Creates the tables of the application.
  ///
  /// The tables of `limpid_sync` are created by Drift itself, during the
  /// migration of the [SyncDatabase]. The memberships of the projects are
  /// created by their own store: they belong to the scoped reads, not to the
  /// state the interface displays.
  Future<void> _createSchema() async {
    for (final String statement in localSchemaStatements) {
      await sync.customStatement(statement);
    }
    await _addMissingProjectColumns();
    for (final String statement in projectMembershipSchemaStatements) {
      await sync.customStatement(statement);
    }
  }

  /// Adds the columns the table `projects` gained after its creation.
  ///
  /// SQLite has no `ADD COLUMN IF NOT EXISTS`: the statement is therefore
  /// prepared only when the column is missing. The schema is applied on every
  /// opening, so the column is added exactly once — on the first opening of a
  /// database created by an older version of the application.
  Future<void> _addMissingProjectColumns() async {
    final List<QueryRow> columns = await sync
        .customSelect('PRAGMA table_info(projects)')
        .get();
    final bool isKnown = columns.any(
      (QueryRow column) => column.data['name'] == 'is_public',
    );
    if (isKnown) return;
    await sync.customStatement(
      'ALTER TABLE projects ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0',
    );
  }
}
