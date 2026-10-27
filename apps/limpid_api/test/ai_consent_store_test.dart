import 'package:limpid_api/limpid_api.dart';

import 'helpers/ai_consent_store_contract.dart';
import 'helpers/store_fixture.dart';

void main() {
  runAiConsentStoreContract(name: 'mémoire', build: _inMemoryFixture);
  runAiConsentStoreContract(name: 'SQLite', build: _sqliteFixture);
}

/// Le magasin en mémoire, pour la suite de tests.
Future<AiConsentFixture> _inMemoryFixture() async {
  return AiConsentFixture(
    consents: InMemoryAiConsentStore(),
    dispose: () async {},
  );
}

/// Le magasin SQLite, sur une base migrée.
Future<AiConsentFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();
  return AiConsentFixture(
    consents: SqliteAiConsentStore(database),
    dispose: database.close,
  );
}
