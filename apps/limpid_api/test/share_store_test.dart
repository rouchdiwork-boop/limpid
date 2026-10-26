import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/db/in_memory_share_store.dart';
import 'package:limpid_api/src/db/sqlite_share_store.dart';

import 'helpers/share_store_contract.dart';
import 'helpers/store_fixture.dart';

void main() {
  runShareStoreContract(name: 'mémoire', build: _inMemoryFixture);
  runShareStoreContract(name: 'SQLite', build: _sqliteFixture);
}

/// Le magasin en mémoire, pour la suite de tests.
Future<ShareFixture> _inMemoryFixture() async {
  return ShareFixture(shares: InMemoryShareStore(), dispose: () async {});
}

/// Le magasin SQLite, sur une base migrée.
Future<ShareFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();
  return ShareFixture(
    shares: SqliteShareStore(database),
    dispose: database.close,
  );
}
