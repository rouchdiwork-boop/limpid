import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support.dart';

/// The table `projects` as it was written before the visibility (D-33).
const String _legacyProjectsTable = '''
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT NOT NULL,
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  order_key TEXT NOT NULL,
  series_ids TEXT NOT NULL DEFAULT '[]',
  chapter_ids TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER,
  updated_at INTEGER
)''';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = await openMemoryDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  group('schéma', () {
    test(
      'crée les tables de l’application et celles de la synchronisation',
      () async {
        final tables = await database.sync
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get();
        final Set<Object?> names = tables
            .map((row) => row.data['name'])
            .toSet();

        expect(
          names,
          containsAll(<String>[
            'projects',
            'chapters',
            'scenes',
            'document_index',
            'sync_cursors',
            'preferences',
          ]),
        );
        expect(names, containsAll(<String>['op_queue_rows', 'snapshot_rows']));
      },
    );
  });

  group('projets', () {
    test('écrit puis relit un projet', () async {
      await database.manuscripts.saveProject(projectOf());

      final Project? stored = await database.manuscripts.findProject(
        'project-1',
        'author-1',
      );

      expect(stored, isNotNull);
      expect(stored!.title, 'Les Heures de Cendre');
      expect(stored.synopsis, 'Une archiviste et une cloche.');
      expect(stored.ownerId, const AuthorId('author-1'));
      expect(stored.status, ManuscriptStatus.draft);
    });

    test('met à jour un projet existant', () async {
      await database.manuscripts.saveProject(projectOf());
      await database.manuscripts.saveProject(
        projectOf(title: 'Carnets de dune', status: ManuscriptStatus.writing),
      );

      final Project? stored = await database.manuscripts.findProject(
        'project-1',
        'author-1',
      );

      expect(stored!.title, 'Carnets de dune');
      expect(stored.status, ManuscriptStatus.writing);
      expect(await database.manuscripts.countProjects('author-1'), 1);
    });

    test(
      'classe les projets du plus récemment modifié au plus ancien',
      () async {
        await database.manuscripts.saveProject(
          projectOf(
            id: 'old',
            title: 'Ancien',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await database.manuscripts.saveProject(
          projectOf(
            id: 'recent',
            title: 'Récent',
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );

        final List<Project> projects = await database.manuscripts.listProjects(
          'author-1',
        );

        expect(projects.map((Project p) => p.id.value), <String>[
          'recent',
          'old',
        ]);
      },
    );

    test('renvoie null pour un projet inconnu', () async {
      expect(
        await database.manuscripts.findProject('inconnu', 'author-1'),
        isNull,
      );
    });

    test('écrit puis relit la visibilité d’un projet', () async {
      await database.manuscripts.saveProject(
        projectOf().copyWith(
          status: ManuscriptStatus.published,
          isPublic: true,
        ),
      );

      final Project? stored = await database.manuscripts.findProject(
        'project-1',
        'author-1',
      );

      expect(stored, isNotNull);
      expect(stored!.isPublic, isTrue);
      expect(stored.status, ManuscriptStatus.published);
    });

    test('relit un projet privé comme privé', () async {
      await database.manuscripts.saveProject(projectOf());

      final Project? stored = await database.manuscripts.findProject(
        'project-1',
        'author-1',
      );

      expect(stored, isNotNull);
      expect(stored!.isPublic, isFalse);
    });

    test(
      'ajoute la visibilité à une base créée par une version antérieure',
      () async {
        final Directory directory = await Directory.systemTemp.createTemp(
          'limpid-schema',
        );
        addTearDown(() => directory.delete(recursive: true));
        final File file = File('${directory.path}/limpide.sqlite');

        final Database legacy = sqlite3.open(file.path);
        legacy.execute(_legacyProjectsTable);
        legacy.close();

        final AppDatabase legacyDatabase = await openFileDatabase(file);
        addTearDown(legacyDatabase.close);

        await legacyDatabase.manuscripts.saveProject(
          projectOf().copyWith(status: ManuscriptStatus.published),
        );

        final Project? stored = await legacyDatabase.manuscripts.findProject(
          'project-1',
          'author-1',
        );
        expect(stored, isNotNull);
        expect(stored!.isPublic, isFalse);
      },
    );
  });

  group('chapitres', () {
    test('écrit puis relit un chapitre', () async {
      await database.manuscripts.saveProject(
        projectOf(chapterIds: <ChapterId>[const ChapterId('chapter-1')]),
      );
      await database.manuscripts.saveChapter(
        chapterOf(),
        projectId: 'project-1',
      );

      final Chapter? stored = await database.manuscripts.findChapter(
        'chapter-1',
      );

      expect(stored, isNotNull);
      expect(stored!.title, 'Le premier chapitre');
    });

    test('classe les chapitres dans l’ordre du projet', () async {
      await database.manuscripts.saveProject(
        projectOf(
          chapterIds: <ChapterId>[
            const ChapterId('chapter-2'),
            const ChapterId('chapter-1'),
          ],
        ),
      );
      await database.manuscripts.saveChapter(
        chapterOf(id: 'chapter-1', title: 'Un'),
        projectId: 'project-1',
      );
      await database.manuscripts.saveChapter(
        chapterOf(id: 'chapter-2', title: 'Deux'),
        projectId: 'project-1',
      );

      final List<Chapter> chapters = await database.manuscripts.listChapters(
        'project-1',
      );

      expect(chapters.map((Chapter c) => c.title), <String>['Deux', 'Un']);
    });

    test('résout le projet d’un chapitre que le projet liste', () async {
      await database.manuscripts.saveProject(
        projectOf(chapterIds: <ChapterId>[const ChapterId('chapter-1')]),
      );

      expect(
        await database.manuscripts.resolveChapterProject('chapter-1'),
        'project-1',
      );
      expect(
        await database.manuscripts.resolveChapterProject('inconnu'),
        isNull,
      );
    });
  });

  group('scènes', () {
    test('écrit puis relit une scène', () async {
      await database.manuscripts.saveChapter(
        chapterOf(),
        projectId: 'project-1',
      );
      await database.manuscripts.saveScene(
        sceneOf(wordCount: 42),
        projectId: 'project-1',
      );

      final Scene? stored = await database.manuscripts.findScene('scene-1');

      expect(stored, isNotNull);
      expect(stored!.title, 'La falaise');
      expect(stored.wordCount, 42);
      expect(stored.documentId, const DocumentId('document-1'));
    });

    test('classe les scènes dans l’ordre du chapitre', () async {
      await database.manuscripts.saveChapter(
        chapterOf(),
        projectId: 'project-1',
      );
      await database.manuscripts.saveScene(
        sceneOf(id: 'scene-2', title: 'Deux'),
        projectId: 'project-1',
      );
      await database.manuscripts.saveScene(
        sceneOf(id: 'scene-1', title: 'Un'),
        projectId: 'project-1',
      );

      final List<Scene> scenes = await database.manuscripts.listScenes(
        'chapter-1',
      );

      expect(scenes.length, 2);
    });

    test('indexe le document d’une scène dans son projet', () async {
      await database.manuscripts.saveProject(projectOf());
      await database.manuscripts.saveChapter(
        chapterOf(),
        projectId: 'project-1',
      );
      await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');

      expect(
        await database.manuscripts.findProjectOfDocument('document-1'),
        'project-1',
      );
      final List<DocumentBinding> bindings = await database.manuscripts
          .listDocumentBindings('author-1');
      expect(bindings.length, 1);
      expect(bindings.first.documentId, 'document-1');
      expect(bindings.first.projectId, 'project-1');
    });
  });

  group('préférences', () {
    test('écrit puis relit une préférence', () async {
      await database.manuscripts.writePreference('daily_goal', '2000');

      expect(await database.manuscripts.readPreference('daily_goal'), '2000');
      expect(await database.manuscripts.readPreference('inconnue'), isNull);
    });
  });

  group('curseurs', () {
    test('écrit puis relit le curseur d’un document', () async {
      expect(await database.manuscripts.readCursor('document-1'), 0);

      await database.manuscripts.writeCursor('document-1', 12);

      expect(await database.manuscripts.readCursor('document-1'), 12);
    });
  });

  group('suppression', () {
    test('supprime le projet, ses chapitres et ses scènes', () async {
      await database.manuscripts.saveProject(
        projectOf(chapterIds: <ChapterId>[const ChapterId('chapter-1')]),
      );
      await database.manuscripts.saveChapter(
        chapterOf(),
        projectId: 'project-1',
      );
      await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');

      final List<String> documents = await database.manuscripts.deleteProject(
        'project-1',
      );

      expect(documents, <String>['document-1']);
      expect(
        await database.manuscripts.findProject('project-1', 'author-1'),
        isNull,
      );
      expect(await database.manuscripts.findChapter('chapter-1'), isNull);
      expect(await database.manuscripts.findScene('scene-1'), isNull);
      expect(
        await database.manuscripts.findProjectOfDocument('document-1'),
        isNull,
      );
    });
  });
}
