import 'dart:typed_data';

import 'package:limpid_api/src/db/in_memory_project_store.dart';
import 'package:limpid_api/src/db/in_memory_sync_store.dart';
import 'package:limpid_api/src/db/project_record.dart';
import 'package:limpid_api/src/db/sync_op_record.dart';
import 'package:limpid_api/src/services/account_word_count.dart';
import 'package:limpid_api/src/services/quota_gauges.dart';
import 'package:limpid_api/src/services/storage_usage.dart';
import 'package:limpid_api/src/storage/artifact_keys.dart';
import 'package:limpid_api/src/storage/object_storage.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('mesure du stockage', () {
    late InMemoryProjectStore projects;
    late InMemoryObjectStorage storage;
    late AccountStorageUsage usage;

    setUp(() {
      projects = InMemoryProjectStore();
      storage = InMemoryObjectStorage();
      usage = AccountStorageUsage(projects: projects, storage: storage);
    });

    test('additionne les artefacts des livres du compte', () async {
      final ProjectRecord owned = await _projectOf(projects, 'user-1');
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(owned.id)}livre.epub',
        bytes: _bytes(10),
        contentType: 'application/epub+zip',
      );
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(owned.id)}livre.pdf',
        bytes: _bytes(5),
        contentType: 'application/pdf',
      );
      await storage.put(
        key: '${ArtifactKeys.prefixOfAccount('user-1')}donnees.zip',
        bytes: _bytes(7),
        contentType: 'application/zip',
      );

      expect(await usage.bytesOf('user-1'), 22);
    });

    test('ne compte pas les artefacts d\'un livre partagé', () async {
      final ProjectRecord owned = await _projectOf(projects, 'user-1');
      projects.addMember(
        projectId: owned.id,
        userId: 'user-2',
        role: ProjectRole.coAuthor,
      );
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(owned.id)}livre.epub',
        bytes: _bytes(10),
        contentType: 'application/epub+zip',
      );

      expect(await usage.bytesOf('user-1'), 10);
      expect(await usage.bytesOf('user-2'), 0);
    });

    test('ne compte pas les artefacts d\'un autre compte', () async {
      await _projectOf(projects, 'user-2');
      await storage.put(
        key: '${ArtifactKeys.prefixOfAccount('user-2')}donnees.zip',
        bytes: _bytes(7),
        contentType: 'application/zip',
      );

      expect(await usage.bytesOf('user-1'), 0);
    });

    test('vaut zéro pour un compte sans artefact', () async {
      await _projectOf(projects, 'user-1');

      expect(await usage.bytesOf('user-1'), 0);
    });
  });

  group('mesure des mots', () {
    late InMemoryProjectStore projects;
    late InMemorySyncStore sync;

    setUp(() {
      projects = InMemoryProjectStore();
      sync = InMemorySyncStore();
    });

    test('compte la prose vivante des livres du compte', () async {
      final ProjectRecord project = await _projectOf(projects, 'user-1');
      await _append(sync, project.id, <String, Object?>{
        'block_id': 'block-1',
        'parent_id': null,
        'order_key': '5',
        'type': 'heading1',
        'content': 'Chapitre premier',
      });
      await _append(sync, project.id, <String, Object?>{
        'block_id': 'block-2',
        'parent_id': 'block-1',
        'order_key': '7',
        'type': 'paragraph',
        'content': 'Il pleuvait sur la falaise.',
      });

      final AccountWordCounter counter = AccountWordCounter(
        projects: projects,
        sync: sync,
      );

      // Le titre n'est pas de la prose : seuls les cinq mots du paragraphe
      // comptent.
      expect(await counter.countOf('user-1'), 5);
    });

    test('s\'arrête au plafond de la formule', () async {
      final ProjectRecord project = await _projectOf(projects, 'user-1');
      await _append(sync, project.id, <String, Object?>{
        'block_id': 'block-1',
        'parent_id': null,
        'order_key': '5',
        'type': 'paragraph',
        'content': 'un deux trois quatre cinq six sept huit',
      });

      final AccountWordCounter counter = AccountWordCounter(
        projects: projects,
        sync: sync,
      );

      expect(await counter.countOf('user-1', ceiling: 3), 3);
    });
  });

  group('jauges du compte', () {
    test('portent les trois valeurs mesurées', () async {
      final InMemoryProjectStore projects = InMemoryProjectStore();
      final InMemorySyncStore sync = InMemorySyncStore();
      final InMemoryObjectStorage storage = InMemoryObjectStorage();

      final ProjectRecord project = await _projectOf(projects, 'user-1');
      await _append(sync, project.id, <String, Object?>{
        'block_id': 'block-1',
        'parent_id': null,
        'order_key': '5',
        'type': 'paragraph',
        'content': 'Il pleuvait sur la falaise.',
      });
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(project.id)}livre.epub',
        bytes: _bytes(12),
        contentType: 'application/epub+zip',
      );

      final AccountQuotaGauges reader = AccountQuotaGauges(
        projects: projects,
        sync: sync,
        storage: storage,
      );
      final QuotaGauges gauges = await reader.read('user-1');

      expect(gauges.projects, 1);
      expect(gauges.words, 5);
      expect(gauges.storageBytes, 12);
    });
  });
}

/// Crée un livre possédé par [ownerId].
Future<ProjectRecord> _projectOf(
  InMemoryProjectStore projects,
  String ownerId,
) {
  return projects.create(
    ownerId: ownerId,
    title: 'Manuscrit',
    synopsis: '',
    status: ManuscriptStatus.draft,
    language: 'fr-FR',
    orderKey: OrderKey.initial.value,
  );
}

/// Ajoute un bloc au livre [projectId].
Future<void> _append(
  InMemorySyncStore sync,
  String projectId,
  Map<String, Object?> payload,
) async {
  final int lamport = sync.storedOperations(projectId).length + 1;
  await sync.append(
    projectId: projectId,
    operations: <SyncOpRecord>[
      SyncOpRecord(
        opId: 'op-$lamport',
        projectId: projectId,
        docId: 'doc-1',
        lamport: lamport,
        authorId: 'user-1',
        type: 'insertBlock',
        payload: payload,
        schemaVersion: 1,
        createdAt: DateTime.utc(2026, 10, 26, 9),
      ),
    ],
  );
}

/// Les octets d'une taille donnée.
Uint8List _bytes(int length) => Uint8List.fromList(List<int>.filled(length, 0));
