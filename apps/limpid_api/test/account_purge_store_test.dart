import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'helpers/account_purge_contract.dart';
import 'helpers/store_fixture.dart';
import 'helpers/test_server.dart';

void main() {
  for (final MapEntry<String, Future<AccountPurgeFixture> Function()> entry
      in <String, Future<AccountPurgeFixture> Function()>{
        'mémoire': _inMemoryFixture,
        'SQLite': _sqliteFixture,
      }.entries) {
    runAccountPurgeContract(name: entry.key, build: entry.value);
  }
}

/// Builds the fixture of the in-memory store.
Future<AccountPurgeFixture> _inMemoryFixture() async {
  final InMemoryAuditLog audit = InMemoryAuditLog();
  final InMemoryAccountPurgeStore store = InMemoryAccountPurgeStore(
    entries: audit.entries,
  );

  return AccountPurgeFixture(
    store: store,
    journal: (AuditEntry entry) async {
      audit.entries.add(entry);
    },
    seed: (String userId) async {
      store.addProject(projectId: 'project-$userId', ownerId: userId);
      store.addOperation(
        operationId: 'op-$userId',
        projectId: 'project-$userId',
        authorId: userId,
      );
      store.addMember(projectId: 'project-$userId', userId: userId);
    },
    remainingRows: (String userId) async => store.remainingRows(userId),
    dispose: () async {},
  );
}

/// Builds the fixture of the SQLite store, on an in-memory database.
Future<AccountPurgeFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();

  final SqliteProjectStore projects = SqliteProjectStore(database);
  final SqliteSyncStore sync = SqliteSyncStore(database);
  final SqliteAuditLog audit = SqliteAuditLog(database);

  return AccountPurgeFixture(
    store: SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database)),
    journal: (AuditEntry entry) => audit.record(entry),
    seed: (String userId) async {
      final ProjectRecord project = await projects.create(
        ownerId: userId,
        title: 'Le livre',
        synopsis: 'Un synopsis.',
        status: ManuscriptStatus.draft,
        language: 'fr-FR',
        orderKey: '5',
      );
      await sync.append(
        projectId: project.id,
        operations: <SyncOpRecord>[
          SyncOpRecord(
            opId: 'op-$userId',
            projectId: project.id,
            docId: 'doc-1',
            lamport: 1,
            authorId: userId,
            type: 'insertBlock',
            payload: <String, dynamic>{'block_id': 'block-1'},
            schemaVersion: 1,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      await database.run(() {
        database.connection.execute(
          'INSERT INTO project_members '
          '(project_id, user_id, role, created_at) VALUES (?, ?, ?, ?)',
          <Object?>[
            project.id,
            userId,
            ProjectRole.coAuthor.name,
            SqliteValues.encodeTimestamp(DateTime.utc(2026, 1, 1)),
          ],
        );
      });
    },
    remainingRows: (String userId) async => _remainingRows(database, userId),
    dispose: database.close,
  );
}

/// The number of rows of the account left in the database.
Future<int> _remainingRows(SqliteDatabase database, String userId) async {
  return database.run(() {
    final ResultSet result = database.connection.select(
      'SELECT (SELECT count(*) FROM projects WHERE owner_id = ?) '
      '+ (SELECT count(*) FROM sync_ops WHERE author_id = ?) '
      '+ (SELECT count(*) FROM project_members WHERE user_id = ?) '
      '+ (SELECT count(*) FROM comments WHERE author_id = ?) AS total',
      <Object?>[userId, userId, userId, userId],
    );
    return result.isEmpty ? 0 : result.first['total']! as int;
  });
}
