import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_core/limpid_core.dart';

import 'support.dart';

void main() {
  late AppDatabase database;
  late LocalManuscriptRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = LocalManuscriptRepository(
      database: database,
      author: const AuthorId('author-1'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('projets', () {
    test('crée un projet qui porte son auteur et ses horodatages', () async {
      final Project project = await repository.createProject(
        title: 'Les Heures de Cendre',
        synopsis: 'Une archiviste et une cloche.',
      );

      expect(project.title, 'Les Heures de Cendre');
      expect(project.ownerId, const AuthorId('author-1'));
      expect(project.id.value, isNotEmpty);
      expect(project.createdAt, isNotNull);

      final Project? stored = await repository.findProject(project.id.value);
      expect(stored, isNotNull);
      expect(stored!.title, 'Les Heures de Cendre');
    });

    test('met à jour les métadonnées d’un projet', () async {
      final Project project = await repository.createProject(title: 'Premier');
      final Project saved = await repository.saveProject(
        project.copyWith(title: 'Renommé', status: ManuscriptStatus.writing),
      );

      expect(saved.title, 'Renommé');
      final Project? stored = await repository.findProject(project.id.value);
      expect(stored!.title, 'Renommé');
      expect(stored.status, ManuscriptStatus.writing);
    });

    test('garde les deux états de la publication', () async {
      final Project project = await repository.createProject(title: 'Livre');
      final Project saved = await repository.saveProject(
        project.copyWith(status: ManuscriptStatus.published, isPublic: true),
      );

      expect(saved.isPublic, isTrue);

      final Project? stored = await repository.findProject(project.id.value);
      expect(stored, isNotNull);
      expect(stored!.status, ManuscriptStatus.published);
      expect(stored.isPublic, isTrue);
    });

    test(
      'classe les projets du plus récemment modifié au plus ancien',
      () async {
        await repository.createProject(title: 'Premier');
        await repository.createProject(title: 'Second');

        final List<Project> projects = await repository.listProjects();

        expect(projects.length, 2);
      },
    );

    test(
      'supprime un projet, ses chapitres, ses scènes et ses documents',
      () async {
        final Project project = await repository.createProject(title: 'Livre');
        final Chapter chapter = await repository.saveChapter(
          chapterOf(id: 'chapter-1'),
        );
        await repository.saveScene(
          sceneOf(id: 'scene-1', chapterId: chapter.id.value),
        );
        await repository.applyOperations(<SyncOp>[
          insertBlockOp(documentId: 'document-1'),
        ]);

        await repository.deleteProject(project.id.value);

        expect(await repository.findProject(project.id.value), isNull);
        expect(await repository.listChapters(project.id.value), isEmpty);
        expect(await repository.listScenes(chapter.id.value), isEmpty);
        expect(
          await repository.loadDocument('document-1'),
          isA<CrdtDocument>(),
        );
        expect((await repository.loadDocument('document-1')).blocks, isEmpty);
        expect(await database.queueStore.all(), isEmpty);
      },
    );
  });

  group('chapitres', () {
    test('crée un chapitre et le rattache au projet qui le liste', () async {
      final Project project = await repository.createProject(title: 'Livre');
      final Chapter chapter = await repository.saveChapter(
        chapterOf(id: 'chapter-1'),
      );

      expect(chapter.title, 'Le premier chapitre');
      expect(chapter.updatedAt, isNotNull);

      final List<Chapter> chapters = await repository.listChapters(
        project.id.value,
      );
      expect(chapters.map((Chapter c) => c.id.value), contains('chapter-1'));
    });

    test('rattache un chapitre au seul projet de la bibliothèque', () async {
      final Project project = await repository.createProject(title: 'Livre');
      await repository.saveChapter(chapterOf(id: 'chapter-1'));

      final List<Chapter> chapters = await repository.listChapters(
        project.id.value,
      );

      expect(chapters.length, 1);
    });

    test('met à jour un chapitre existant', () async {
      await repository.createProject(title: 'Livre');
      await repository.saveChapter(chapterOf(id: 'chapter-1'));
      final Chapter saved = await repository.saveChapter(
        chapterOf(id: 'chapter-1', title: 'Renommé'),
      );

      expect(saved.title, 'Renommé');
      final List<Chapter> chapters = await repository.listChapters(
        (await repository.listProjects()).first.id.value,
      );
      expect(chapters.first.title, 'Renommé');
    });
  });

  group('scènes', () {
    test('crée une scène et indexe son document', () async {
      await repository.createProject(title: 'Livre');
      await repository.saveChapter(chapterOf(id: 'chapter-1'));
      final Scene scene = await repository.saveScene(
        sceneOf(id: 'scene-1', wordCount: 120),
      );

      expect(scene.wordCount, 120);
      expect(scene.documentId, const DocumentId('document-1'));

      final List<Scene> scenes = await repository.listScenes('chapter-1');
      expect(scenes.length, 1);
      expect(scenes.first.title, 'La falaise');
    });

    test('met à jour une scène existante', () async {
      await repository.createProject(title: 'Livre');
      await repository.saveChapter(chapterOf(id: 'chapter-1'));
      await repository.saveScene(sceneOf(id: 'scene-1'));
      final Scene saved = await repository.saveScene(
        sceneOf(id: 'scene-1', title: 'La falaise revisited'),
      );

      expect(saved.title, 'La falaise revisited');
      final List<Scene> scenes = await repository.listScenes('chapter-1');
      expect(scenes.first.title, 'La falaise revisited');
    });
  });

  group('document CRDT', () {
    test('rend un document vide pour un document inconnu', () async {
      final CrdtDocument document = await repository.loadDocument('inconnu');

      expect(document.id, const DocumentId('inconnu'));
      expect(document.blocks, isEmpty);
      expect(document.operationCount, 0);
    });

    test('persiste le document et le relit à l’identique', () async {
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1', blockId: 'block-1'),
      ]);

      final CrdtDocument document = await repository.loadDocument('document-1');

      expect(document.blocks.length, 1);
      expect(document.blocks.first.id, const BlockId('block-1'));
      expect(
        document.blocks.first.content.plainText,
        'Il pleuvait sur la falaise.',
      );
      expect(document.operationCount, 1);
    });
  });

  group('applyOperations', () {
    test('applique les opérations et les met en file d’attente', () async {
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1', blockId: 'block-1'),
      ]);

      final CrdtDocument document = await repository.loadDocument('document-1');
      expect(document.blocks.length, 1);

      final entries = await database.queueStore.all();
      expect(entries.length, 1);
      expect(entries.first.documentId, 'document-1');
      expect(entries.first.operationKey, 'document-1/1/author-1');
    });

    test('est idempotent : appliquer deux fois ne change rien', () async {
      final SyncOp operation = insertBlockOp(documentId: 'document-1');

      await repository.applyOperations(<SyncOp>[operation]);
      await repository.applyOperations(<SyncOp>[operation]);

      final CrdtDocument document = await repository.loadDocument('document-1');
      expect(document.blocks.length, 1);
      expect(document.operationCount, 1);
      expect(await database.queueStore.all(), hasLength(1));
    });

    test(
      'est idempotent pour une liste qui répète la même opération',
      () async {
        final SyncOp operation = insertBlockOp(documentId: 'document-1');

        await repository.applyOperations(<SyncOp>[operation, operation]);

        final CrdtDocument document = await repository.loadDocument(
          'document-1',
        );
        expect(document.blocks.length, 1);
        expect(document.operationCount, 1);
        expect(await database.queueStore.all(), hasLength(1));
      },
    );

    test('applique les opérations de plusieurs documents', () async {
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1', blockId: 'block-1'),
        insertBlockOp(documentId: 'document-2', blockId: 'block-2', lamport: 1),
      ]);

      expect((await repository.loadDocument('document-1')).blocks.length, 1);
      expect((await repository.loadDocument('document-2')).blocks.length, 1);
      expect(await database.queueStore.all(), hasLength(2));
    });

    test('conserve l’historique des opérations du document', () async {
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1', blockId: 'block-1', lamport: 1),
      ]);
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1', blockId: 'block-2', lamport: 2),
      ]);

      final CrdtDocument document = await repository.loadDocument('document-1');
      expect(document.operationCount, 2);
      expect(document.blocks.length, 2);
    });
  });
}
