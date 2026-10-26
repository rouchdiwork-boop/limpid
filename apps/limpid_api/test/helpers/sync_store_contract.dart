import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

import 'store_fixture.dart';

/// Runs the contract of [SyncStore].
///
/// The same scenarios run against the in-memory store and against the SQLite
/// one: the equality of the two runs is the proof that the development
/// database behaves like the reference implementation.
void runSyncStoreContract({
  required String name,
  required Future<StoreFixture> Function() build,
}) {
  group('contrat des dépôts — $name', () {
    late StoreFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    group('journal de synchronisation', () {
      test('accepte une opération', () async {
        final String projectId = await createProjectId(fixture);

        final AppendResult result = await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 1),
          ],
        );

        expect(result.accepted, hasLength(1));
        expect(result.duplicated, isEmpty);
        expect(result.maxLamport, 1);
        expect(result.accepted.first.docId, 'doc-1');
        expect(result.accepted.first.authorId, 'user-1');
        expect(result.accepted.first.type, 'insertBlock');
        expect(result.accepted.first.schemaVersion, 1);
        expect(result.accepted.first.payload, <String, dynamic>{
          'block_id': 'block-1',
          'content': 'Il pleuvait sur la falaise.',
        });
      });

      test('est idempotent sur (doc, lamport, author)', () async {
        final String projectId = await createProjectId(fixture);
        final SyncOpRecord operation = buildOperation(
          projectId: projectId,
          lamport: 1,
        );

        await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[operation],
        );
        final AppendResult result = await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[operation],
        );

        expect(result.accepted, isEmpty);
        expect(result.duplicated, hasLength(1));
        expect(result.duplicated.first, same(operation));
        expect(result.maxLamport, 1);
      });

      test('renvoie le plus haut lamport du projet', () async {
        final String projectId = await createProjectId(fixture);

        final AppendResult result = await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 5),
            buildOperation(projectId: projectId, lamport: 3, opId: 'op-3'),
          ],
        );

        expect(result.accepted, hasLength(2));
        expect(result.maxLamport, 5);
      });

      test('accepte un lot vide', () async {
        final String projectId = await createProjectId(fixture);

        final AppendResult result = await fixture.sync.append(
          projectId: projectId,
          operations: const <SyncOpRecord>[],
        );

        expect(result.accepted, isEmpty);
        expect(result.duplicated, isEmpty);
        expect(result.maxLamport, 0);
      });

      test('lit les opérations postérieures à un lamport', () async {
        final String projectId = await createProjectId(fixture);
        await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 1),
            buildOperation(projectId: projectId, lamport: 2, opId: 'op-2'),
          ],
        );

        final List<SyncOpRecord> recent = await fixture.sync.since(
          projectId: projectId,
          lamport: 1,
          limit: 10,
        );

        expect(recent, hasLength(1));
        expect(recent.first.lamport, 2);
      });

      test('respecte la limite de lecture', () async {
        final String projectId = await createProjectId(fixture);
        await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 1),
            buildOperation(projectId: projectId, lamport: 2, opId: 'op-2'),
            buildOperation(projectId: projectId, lamport: 3, opId: 'op-3'),
          ],
        );

        final List<SyncOpRecord> recent = await fixture.sync.since(
          projectId: projectId,
          lamport: 0,
          limit: 2,
        );

        expect(recent, hasLength(2));
        expect(recent.first.lamport, 1);
        expect(recent.last.lamport, 2);
      });

      test('lit tout le journal du projet', () async {
        final String projectId = await createProjectId(fixture);
        await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 2, opId: 'op-2'),
            buildOperation(projectId: projectId, lamport: 1),
          ],
        );

        final List<SyncOpRecord> operations = await fixture.sync.all(
          projectId: projectId,
        );

        expect(operations, hasLength(2));
        expect(operations.first.lamport, 1);
        expect(operations.last.lamport, 2);
      });

      test('renvoie un journal vide pour un projet inconnu', () async {
        final List<SyncOpRecord> operations = await fixture.sync.all(
          projectId: 'projet-inconnu',
        );

        expect(operations, isEmpty);
      });

      test('répond les projets qui possèdent un document', () async {
        final String projectId = await createProjectId(fixture);

        expect(await fixture.sync.projectsOfDocument('doc-1'), isEmpty);

        await fixture.sync.append(
          projectId: projectId,
          operations: <SyncOpRecord>[
            buildOperation(projectId: projectId, lamport: 1),
          ],
        );

        expect(await fixture.sync.projectsOfDocument('doc-1'), <String>{
          projectId,
        });
        expect(await fixture.sync.projectsOfDocument('doc-2'), isEmpty);
      });
    });
  });
}
