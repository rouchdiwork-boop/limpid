import 'dart:io';

import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';

/// Checks the Postgres path: migrations, project store and sync store.
///
/// Run with `dart run tool/postgres_check.dart` against a local Postgres.
Future<void> main(List<String> arguments) async {
  final String databaseUrl = arguments.isEmpty
      ? 'postgres://postgres:postgres@127.0.0.1:55432/limpid'
      : arguments.first;

  final Pool<Object?> pool = createPool(databaseUrl);
  final List<String> applied = await MigrationRunner(
    pool: pool,
    directory: 'db/migrations',
  ).run();
  stdout.writeln('Migrations appliquées : $applied');

  final List<String> again = await MigrationRunner(
    pool: pool,
    directory: 'db/migrations',
  ).run();
  stdout.writeln('Migrations rejouées (doit être vide) : $again');

  final PostgresProjectStore projects = PostgresProjectStore(pool);
  final PostgresSyncStore sync = PostgresSyncStore(pool);
  final PostgresAuditLog audit = PostgresAuditLog(pool);

  final ProjectRecord project = await projects.create(
    ownerId: 'user-1',
    title: 'Titre',
    synopsis: 'Synopsis',
    status: ManuscriptStatus.draft,
    language: 'fr-FR',
    orderKey: '5',
  );
  stdout.writeln('Projet créé : ${project.id}');

  final ProjectPage page = await projects.list(
    userId: 'user-1',
    limit: 10,
    cursor: null,
  );
  stdout.writeln('Projets listés : ${page.items.length} / total ${page.total}');

  final ProjectAccess? access = await projects.access(
    projectId: project.id,
    userId: 'user-1',
  );
  stdout.writeln('Rôle : ${access?.role.name}');

  final ProjectAccess? hidden = await projects.access(
    projectId: project.id,
    userId: 'user-2',
  );
  stdout.writeln('Accès d\'un tiers : $hidden');

  final SyncOpRecord operation = SyncOpRecord(
    opId: 'op-1',
    projectId: project.id,
    docId: 'doc-1',
    lamport: 1,
    authorId: 'user-1',
    type: 'insertBlock',
    payload: <String, dynamic>{
      'block_id': 'block-1',
      'parent_id': null,
      'order_key': '5',
      'type': 'paragraph',
      'content': 'Il pleuvait sur la falaise.',
    },
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );

  final AppendResult first = await sync.append(
    projectId: project.id,
    operations: <SyncOpRecord>[operation],
  );
  stdout.writeln('Acceptées : ${first.accepted.length}');

  final AppendResult second = await sync.append(
    projectId: project.id,
    operations: <SyncOpRecord>[operation],
  );
  stdout.writeln('Doublons : ${second.duplicated.length}');

  final List<SyncOpRecord> pulled = await sync.since(
    projectId: project.id,
    lamport: 0,
    limit: 10,
  );
  stdout.writeln('Opérations relues : ${pulled.length}');

  final List<DocumentTree> trees = TreeBuilder.build(
    await sync.all(projectId: project.id),
  );
  stdout.writeln(
    'Arbre : ${trees.length} document(s), '
    '${trees.first.blocks.length} bloc(s) racine',
  );

  await audit.record(
    AuditEntry(
      userId: 'user-1',
      action: 'project.deleted',
      targetType: 'project',
      targetId: project.id,
      metadata: <String, Object?>{'title': project.title},
    ),
  );
  stdout.writeln('Audit écrit.');

  await projects.softDelete(projectId: project.id);
  final ProjectAccess? deleted = await projects.access(
    projectId: project.id,
    userId: 'user-1',
  );
  stdout.writeln('Projet après suppression : $deleted');

  await pool.close();
  stdout.writeln('OK');
}
