import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/data/local_publication_repository.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_core/limpid_core.dart';

import 'support.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = await openMemoryDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  /// The repository of an author, on top of the local database.
  LocalManuscriptRepository repositoryOf(String authorId) =>
      LocalManuscriptRepository(database: database, author: AuthorId(authorId));

  group('effacement des données locales', () {
    test('vide la base : ni projet, ni chapitre, ni scène, ni document, '
        'ni opération, ni préférence', () async {
      final LocalManuscriptRepository repository = repositoryOf('author-1');
      final Project project = await repository.createProject(
        title: 'Les Heures de Cendre',
      );
      final Chapter chapter = await repository.saveChapter(
        chapterOf(id: 'chapter-1'),
      );
      await repository.saveScene(
        sceneOf(id: 'scene-1', chapterId: chapter.id.value),
      );
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1'),
      ]);
      await database.manuscripts.writePreference('daily_goal', '1500');

      await database.wiper.wipe();

      expect(await database.manuscripts.listProjects('author-1'), isEmpty);
      expect(
        await database.manuscripts.findProject(project.id.value, 'author-1'),
        isNull,
      );
      expect(
        await database.manuscripts.listChapters(project.id.value),
        isEmpty,
      );
      expect(await database.manuscripts.listScenes(chapter.id.value), isEmpty);
      expect(
        await database.manuscripts.findProjectOfDocument('document-1'),
        isNull,
      );
      expect(await database.manuscripts.readCursor('document-1'), 0);
      expect(await database.manuscripts.readPreference('daily_goal'), isNull);
      expect(await database.queueStore.all(), isEmpty);
      expect(
        await database.snapshots.read(const DocumentId('document-1')),
        isNull,
      );
    });

    test('est idempotent : effacer deux fois ne change rien', () async {
      final LocalManuscriptRepository repository = repositoryOf('author-1');
      await repository.createProject(title: 'Les Heures de Cendre');
      await repository.applyOperations(<SyncOp>[
        insertBlockOp(documentId: 'document-1'),
      ]);

      await database.wiper.wipe();
      await database.wiper.wipe();

      expect(await database.manuscripts.listProjects('author-1'), isEmpty);
      expect(await database.queueStore.all(), isEmpty);
      expect(
        await database.snapshots.read(const DocumentId('document-1')),
        isNull,
      );
    });
  });

  group('lecture par compte', () {
    test('la bibliothèque ne montre que les projets de son auteur', () async {
      final LocalManuscriptRepository first = repositoryOf('author-1');
      final LocalManuscriptRepository second = repositoryOf('author-2');

      await first.createProject(title: 'Le livre de A');
      final Project book = await second.createProject(title: 'Le livre de B');

      final List<Project> projects = await first.listProjects();
      expect(projects.map((Project project) => project.title), <String>[
        'Le livre de A',
      ]);
      expect(await first.findProject(book.id.value), isNull);
      expect(await second.findProject(book.id.value), isNotNull);
    });

    test('un projet partagé reste visible pour son collaborateur', () async {
      final LocalManuscriptRepository collaborator = repositoryOf('author-1');
      final LocalManuscriptRepository owner = repositoryOf('author-2');

      await collaborator.saveProject(
        projectOf(
          id: 'shared',
          authorId: 'author-2',
          title: 'Le livre partagé',
        ),
      );

      final List<Project> projects = await collaborator.listProjects();
      expect(projects.map((Project project) => project.id.value), <String>[
        'shared',
      ]);
      expect(await collaborator.findProject('shared'), isNotNull);
      expect(await owner.findProject('shared'), isNotNull);
    });

    test(
      'le livre publié de l’auteur reste lisible par la vitrine locale',
      () async {
        final LocalManuscriptRepository author = repositoryOf('author-1');
        await author.saveProject(
          projectOf(
            id: 'published',
            authorId: 'author-1',
            title: 'Le livre publié',
            status: ManuscriptStatus.published,
            isPublic: true,
          ),
        );
        await author.saveChapter(chapterOf(id: 'chapter-1'));
        await author.saveScene(sceneOf(id: 'scene-1', chapterId: 'chapter-1'));

        final Publication publication = await LocalPublicationRepository(
          manuscript: author,
        ).load(projectId: 'published');

        expect(publication, isA<PublishedBook>());
        expect((publication as PublishedBook).project.id.value, 'published');
      },
    );

    test(
      'un visiteur sans compte voit le livre en vitrine de la base locale',
      () async {
        final LocalManuscriptRepository author = repositoryOf('author-1');
        await author.saveProject(
          projectOf(
            id: 'published',
            authorId: 'author-1',
            title: 'Le livre publié',
            status: ManuscriptStatus.published,
            isPublic: true,
          ),
        );
        await author.saveChapter(chapterOf(id: 'chapter-1'));

        final Publication publication = await LocalPublicationRepository(
          manuscript: repositoryOf('visitor'),
        ).load(projectId: 'published');

        expect(publication, isA<PublishedBook>());
      },
    );

    test(
      'un livre publié mais hors vitrine reste invisible pour un visiteur',
      () async {
        final LocalManuscriptRepository author = repositoryOf('author-1');
        await author.saveProject(
          projectOf(
            id: 'publie',
            authorId: 'author-1',
            title: 'Le livre publié',
            status: ManuscriptStatus.published,
          ),
        );

        final Publication publication = await LocalPublicationRepository(
          manuscript: repositoryOf('visitor'),
        ).load(projectId: 'publie');

        // D-33 : « publié » ne veut pas dire « en vitrine ».
        expect(publication, isA<UnknownBook>());
      },
    );

    test(
      'un projet qui n’est pas publié reste invisible pour un visiteur',
      () async {
        final LocalManuscriptRepository author = repositoryOf('author-1');
        await author.saveProject(
          projectOf(id: 'draft', authorId: 'author-1', title: 'Le brouillon'),
        );

        final Publication publication = await LocalPublicationRepository(
          manuscript: repositoryOf('visitor'),
        ).load(projectId: 'draft');

        expect(publication, isA<UnknownBook>());
      },
    );
  });
}
