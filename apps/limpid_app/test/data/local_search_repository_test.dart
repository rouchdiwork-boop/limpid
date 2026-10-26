import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_search_repository.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

import 'support.dart';

/// The account that owns the manuscripts of the tests.
const String _accountId = 'author-1';

/// The budget of a search on a corpus of a hundred thousand words.
///
/// The criterion of the lot 1 gives a hundred and twenty milliseconds for a
/// million of words: the test measures a tenth of the corpus and keeps the
/// same budget. The measure at a million words belongs to the list of the
/// pre-delivery.
const Duration _searchBudget = Duration(milliseconds: 120);

/// The number of blocks of the corpus of the budget.
///
/// Every block holds a hundred and forty words: the corpus holds a hundred
/// thousand words.
const int _budgetBlocks = 700;

/// Writes a document made of one block per text.
Future<void> writeDocument(
  AppDatabase database,
  String documentId,
  List<String> texts,
) async {
  OrderKey order = OrderKey.initial;
  final List<SyncOp> operations = <SyncOp>[];
  for (int index = 0; index < texts.length; index++) {
    order = OrderKey.between(order, null);
    operations.add(
      InsertBlockOp(
        doc: DocumentId(documentId),
        lamport: index + 1,
        author: const AuthorId(_accountId),
        blockId: BlockId('block-$index'),
        parent: null,
        order: order,
        type: BlockType.paragraph,
        content: TextContent(texts[index]),
      ),
    );
  }
  await database
      .snapshotsFor(() => _accountId)
      .write(
        DocumentSnapshot(
          documentId: DocumentId(documentId),
          since: 0,
          maxLamport: texts.length,
          operations: operations,
        ),
      );
}

void main() {
  late AppDatabase database;
  late LocalSearchRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = LocalSearchRepository(
      database: database,
      currentAuthor: () => const AuthorId(_accountId),
    );
    await database.manuscripts.saveProject(
      projectOf(id: 'project-1', authorId: _accountId),
    );
    await database.manuscripts.saveChapter(chapterOf(), projectId: 'project-1');
    await database.manuscripts.saveScene(
      sceneOf(id: 'scene-1', documentId: 'document-1', title: 'Le quai'),
      projectId: 'project-1',
      accountId: _accountId,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('la recherche trouve', () {
    test('un mot qui est dans le texte d\'un bloc', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
        'Le vent portait la pluie jusqu\'au port.',
      ]);

      final List<SearchResult> results = await repository.search('falaise');

      expect(results, hasLength(1));
      expect(results.first.blockId, 'block-0');
      expect(results.first.sceneId, 'scene-1');
      expect(results.first.sceneTitle, 'Le quai');
      expect(results.first.projectTitle, 'Les Heures de Cendre');
      expect(results.first.excerpt, contains('falaise'));
    });

    test('le titre de la scène', () async {
      await writeDocument(database, 'document-1', <String>[
        'Un matin ordinaire.',
      ]);

      final List<SearchResult> results = await repository.search('quai');

      expect(results, isNotEmpty);
      expect(results.first.sceneTitle, 'Le quai');
      expect(results.first.isBlock, isFalse);
    });

    test('le titre du projet', () async {
      await writeDocument(database, 'document-1', <String>[
        'Un matin ordinaire.',
      ]);

      final List<SearchResult> results = await repository.search('Cendre');

      expect(results, isNotEmpty);
      expect(results.first.projectTitle, 'Les Heures de Cendre');
    });

    test('un mot qui n\'est dans aucun texte', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);

      final List<SearchResult> results = await repository.search('hippopotame');

      expect(results, isEmpty);
    });
  });

  group('la requête', () {
    test('vide ne renvoie rien et ne balaye pas l\'index', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);

      expect(await repository.search(''), isEmpty);
      expect(await repository.search('   '), isEmpty);
    });

    test('ne lève pas d\'erreur quand elle porte la syntaxe de FTS5', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);

      expect(await repository.search('"'), isEmpty);
      expect(await repository.search('*'), isEmpty);
      expect(await repository.search(':'), isEmpty);
      expect(await repository.search('falaise*'), hasLength(1));
      expect(await repository.search('"falaise"'), hasLength(1));
      expect(await repository.search('NEAR('), isEmpty);
    });

    test('ignore les accents pour trouver le mot', () async {
      await writeDocument(database, 'document-1', <String>[
        'Le café était déjà froid.',
      ]);

      expect(await repository.search('cafe'), hasLength(1));
      expect(await repository.search('café'), hasLength(1));
    });
  });

  group('la pertinence', () {
    test('classe le passage qui répète le mot en premier', () async {
      await writeDocument(database, 'document-1', <String>[
        'La falaise est longue, et la falaise est nue, et la falaise attend.',
        'Un rocher, parfois, où la falaise se reflète.',
      ]);

      final List<SearchResult> results = await repository.search('falaise');

      expect(results.length, greaterThan(1));
      expect(results.first.blockId, 'block-0');
      expect(results.first.relevance, greaterThan(results.last.relevance));
    });

    test('classe les passages de façon stable', () async {
      await writeDocument(database, 'document-1', <String>[
        'Un rocher, parfois.',
        'La falaise attend.',
      ]);

      final List<SearchResult> first = await repository.search('falaise');
      final List<SearchResult> second = await repository.search('falaise');

      expect(
        second.map((SearchResult result) => result.blockId),
        first.map((SearchResult result) => result.blockId),
      );
    });
  });

  group('l\'index suit la source', () {
    test('retrouve un bloc modifié avec son nouveau texte', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);
      expect(await repository.search('falaise'), hasLength(1));

      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise et sur le phare.',
      ]);

      final List<SearchResult> results = await repository.search('phare');
      expect(results, hasLength(1));
      expect(results.first.excerpt, contains('phare'));
    });

    test('ne retrouve plus un bloc supprimé', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);
      expect(await repository.search('falaise'), hasLength(1));

      await writeDocument(database, 'document-1', <String>[
        'Un matin ordinaire.',
      ]);

      expect(await repository.search('falaise'), isEmpty);
    });

    test('ne propose plus un bloc supprimé de la scène', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);
      expect(await repository.search('falaise'), hasLength(1));

      // The block is deleted: the tombstone stays in the journal, and the
      // index must not show the passage anymore.
      await database
          .snapshotsFor(() => _accountId)
          .write(
            DocumentSnapshot(
              documentId: const DocumentId('document-1'),
              since: 0,
              maxLamport: 2,
              operations: <SyncOp>[
                InsertBlockOp(
                  doc: const DocumentId('document-1'),
                  lamport: 1,
                  author: const AuthorId(_accountId),
                  blockId: const BlockId('block-0'),
                  parent: null,
                  order: OrderKey('1'),
                  type: BlockType.paragraph,
                  content: const TextContent('Il pleuvait sur la falaise.'),
                ),
                const DeleteBlockOp(
                  doc: DocumentId('document-1'),
                  lamport: 2,
                  author: AuthorId(_accountId),
                  blockId: BlockId('block-0'),
                ),
              ],
            ),
          );

      expect(await repository.search('falaise'), isEmpty);
    });

    test('retrouve le nouveau titre d\'une scène', () async {
      await writeDocument(database, 'document-1', <String>[
        'Un matin ordinaire.',
      ]);
      expect(await repository.search('quai'), isNotEmpty);

      await database.manuscripts.saveScene(
        sceneOf(id: 'scene-1', documentId: 'document-1', title: 'Le phare'),
        projectId: 'project-1',
        accountId: _accountId,
      );

      expect(await repository.search('quai'), isEmpty);
      expect(await repository.search('phare'), isNotEmpty);
    });

    test('oublie un document qui n\'est plus indexé', () async {
      await writeDocument(database, 'document-1', <String>[
        'Il pleuvait sur la falaise.',
      ]);
      expect(await repository.search('falaise'), hasLength(1));

      await database.manuscripts.deleteProject(
        'project-1',
        accountId: _accountId,
      );

      expect(await repository.search('falaise'), isEmpty);
    });
  });

  group('le budget', () {
    test('cherche dans cent mille mots en moins de 120 ms', () async {
      final List<String> texts = <String>[
        for (int index = 0; index < _budgetBlocks; index++)
          <String>[
            ...List<String>.filled(70, 'alambic'),
            ...List<String>.filled(70, 'cornue'),
          ].join(' '),
      ];
      await writeDocument(database, 'document-1', texts);

      // La premiere recherche construit l'index : elle ne mesure pas la
      // recherche, elle mesure la construction.
      await repository.search('alambic');

      final Stopwatch watch = Stopwatch()..start();
      final List<SearchResult> results = await repository.search('alambic');
      watch.stop();

      expect(results, isNotEmpty);
      expect(watch.elapsed, lessThan(_searchBudget));
    });
  });
}
