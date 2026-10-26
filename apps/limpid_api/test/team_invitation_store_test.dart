import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/db/in_memory_team_invitation_store.dart';
import 'package:limpid_api/src/db/sqlite_team_invitation_store.dart';

import 'helpers/store_fixture.dart';
import 'helpers/team_invitation_store_contract.dart';

void main() {
  runTeamInvitationStoreContract(name: 'mémoire', build: _inMemoryFixture);
  runTeamInvitationStoreContract(name: 'SQLite', build: _sqliteFixture);
}

/// Le magasin en mémoire, pour la suite de tests.
Future<TeamInvitationFixture> _inMemoryFixture() async {
  return TeamInvitationFixture(
    invitations: InMemoryTeamInvitationStore(),
    dispose: () async {},
  );
}

/// Le magasin SQLite, sur une base migrée.
///
/// L'invitation porte une clé étrangère vers l'équipe : la base migrée a
/// besoin d'une équipe avant d'accueillir une invitation.
Future<TeamInvitationFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();
  final int stamp = SqliteValues.encodeTimestamp(DateTime.utc(2026, 11, 1));
  await database.run(() {
    database.connection.execute(
      'INSERT INTO teams (id, name, owner_id, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>['team-1', 'La Brigade', 'owner-1', stamp, stamp],
    );
    // Le contrat invite aussi dans une seconde equipe : la cle etrangere
    // de l'invitation la vise, elle doit donc exister.
    database.connection.execute(
      'INSERT INTO teams (id, name, owner_id, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>['team-2', 'La Compagnie', 'owner-1', stamp, stamp],
    );
  });
  return TeamInvitationFixture(
    invitations: SqliteTeamInvitationStore(database),
    dispose: database.close,
  );
}
