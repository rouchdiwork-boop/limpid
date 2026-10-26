import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/data/account_op_queue_store.dart';
import 'package:limpid_app/src/data/account_snapshot_store.dart';
import 'package:limpid_app/src/data/app_schema.dart';
import 'package:limpid_app/src/data/local_account_scope.dart';
import 'package:limpid_app/src/data/local_data_wiper.dart';
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/project_membership_store.dart';
import 'package:limpid_app/src/data/writing_session_store.dart';
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
///
/// ## The accounts of the device
///
/// The file is unique per device and outlives the session: two accounts
/// share it. [account] names the account the local data belongs to, and the
/// stores that carry the data of an account — the queue, the snapshots —
/// are read through an account-scoped view ([queueFor], [snapshotsFor]).
/// The raw stores stay reachable: they are the storage of the device, not
/// the data of an account.
final class AppDatabase {
  AppDatabase._(this.sync, this.account);

  /// Creates a database on top of [executor].
  ///
  /// The schema is **not** created: call [openWith] to get a ready database.
  AppDatabase.forExecutor(
    QueryExecutor executor, {
    LocalAccountScope? accountScope,
  }) : sync = SyncDatabase(executor),
       account = accountScope ?? LocalAccountScope.live();

  /// The Drift database of the synchronisation: the queue and the snapshots.
  final SyncDatabase sync;

  /// The account that owns the local data of the device.
  final LocalAccountScope account;

  /// The state the interface displays.
  late final ManuscriptStore manuscripts = ManuscriptStore(sync, account);

  /// The writing sessions of the author: the days on which they wrote.
  ///
  /// The store is **local**: the sessions belong to the device and never
  /// reach the server.
  late final WritingSessionStore writingSessions = WritingSessionStore(
    sync,
    account,
  );

  /// The durable queue of the operations waiting to be sent.
  ///
  /// The store is the storage of the **device**: it holds the operations of
  /// every account. The repositories read it through [queueFor], which keeps
  /// the operations of the other accounts out of sight.
  late final DriftOpQueueStore queueStore = DriftOpQueueStore(sync);

  /// The persistence of the CRDT documents of the scenes.
  ///
  /// The view is the one of the account of the session: the CRDT journal of
  /// a manuscript is only served to the account that owns it. The
  /// repositories build their own view with [snapshotsFor].
  late final DriftSnapshotStore snapshotStore = DriftSnapshotStore(sync);

  /// The persistence of the CRDT documents of the scenes, for the account of
  /// the session.
  late final AccountSnapshotStore snapshots = AccountSnapshotStore(
    delegate: snapshotStore,
    accountId: () => account.accountId,
  );

  /// The queue of the operations, with the retry policy of `limpid_sync`.
  ///
  /// The queue is the storage of the **device**: it holds the operations of
  /// every account. The repositories use [queueFor], which keeps the
  /// operations of the other accounts out of sight.
  late final OpQueue queue = OpQueue(store: queueStore);

  /// The service that empties the local data of the author (RGPD).
  ///
  /// The wipe is the right to erasure on the device: once it ran, the
  /// machine holds no manuscript, no scene, no snapshot and no pending
  /// operation of the author.
  late final LocalDataWiper wiper = LocalDataWiper(sync);

  /// The memberships of the projects, for the reads scoped to the author.
  late final ProjectMembershipStore memberships = ProjectMembershipStore(sync);

  /// The queue of the operations of the account [accountId].
  ///
  /// The view hides the operations of the other accounts: the queue of one
  /// account never leaves the device under the session of another.
  AccountOpQueueStore queueFor(String Function() accountId) =>
      AccountOpQueueStore(delegate: queueStore, accountId: accountId);

  /// The snapshots of the documents of the account [accountId].
  ///
  /// The view hides the snapshots of the other accounts: the CRDT journal of
  /// a manuscript is only served to the account that owns it.
  AccountSnapshotStore snapshotsFor(String Function() accountId) =>
      AccountSnapshotStore(delegate: snapshotStore, accountId: accountId);

  /// Opens the local database of the device.
  ///
  /// On mobile and on desktop the file lives in the documents directory of
  /// the application and the connection is hosted by a background isolate:
  /// the persistence never blocks the UI. On the web the connection needs
  /// the WebAssembly backend, and an explicit error is raised when it is
  /// missing.
  ///
  /// The account of the local data follows the live session: the file stays
  /// the same, and the data of an account is only served to that account.
  static Future<AppDatabase> open({
    String name = localDatabaseName,
    LocalAccountScope? accountScope,
  }) async {
    final AppDatabase database = AppDatabase._(
      SyncDatabase(_connection(name)),
      accountScope ?? LocalAccountScope.live(),
    );
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
  static Future<AppDatabase> openWith(
    QueryExecutor executor, {
    LocalAccountScope? accountScope,
  }) async {
    final AppDatabase database = AppDatabase.forExecutor(
      executor,
      accountScope: accountScope,
    );
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
  ///
  /// The schema is applied twice: the second pass recreates the indexes that
  /// the move to the account scope dropped with the tables it rebuilt.
  Future<void> _createSchema() async {
    for (final String statement in localSchemaStatements) {
      await sync.customStatement(statement);
    }
    await _addMissingProjectColumns();
    await _migrateToTheAccountScope();
    for (final String statement in localSchemaStatements) {
      await sync.customStatement(statement);
    }
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

  /// Gives the tables of the local database their account.
  ///
  /// A database created before the account scope holds tables without the
  /// `account_id` column: they are rebuilt, and their rows are kept under
  /// the account of the session — the author who was using the device.
  Future<void> _migrateToTheAccountScope() async {
    for (final AccountScopeMigration migration in accountScopeMigrations) {
      if (await _holdsTheAccountColumn(migration)) continue;
      await _rebuildTheTable(migration);
    }
  }

  /// Whether the table of [migration] already holds the account column.
  Future<bool> _holdsTheAccountColumn(AccountScopeMigration migration) async {
    final List<QueryRow> columns = await sync
        .customSelect(migration.pragma)
        .get();
    return columns.any(
      (QueryRow column) => column.data['name'] == 'account_id',
    );
  }

  /// Rebuilds the table of [migration] with its account column.
  ///
  /// The rows of the previous version are copied under the account of the
  /// session: the author finds their preferences again after the update.
  Future<void> _rebuildTheTable(AccountScopeMigration migration) async {
    await sync.customStatement(migration.rename);
    await sync.customStatement(migration.create);
    await sync.customStatement(migration.copy, <Object>[account.accountId]);
    await sync.customStatement(migration.drop);
  }
}
