import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

/// The title of the published book of the tests.
const String bookTitle = 'Les Heures de Cendre';

/// The synopsis of the published book of the tests.
const String bookSynopsis =
    'Dans un village de pêcheurs qui ne compte plus ses morts.';

/// The first paragraph of the first scene of the book.
const String firstExcerpt = 'La cloche sonna à quatre heures douze.';

/// The second paragraph of the first scene: it must never leave the server.
const String secondParagraph = 'Le sel avait formé sur les vitres une croûte.';

/// The excerpt of the second scene of the book.
const String otherExcerpt = "C'était écrit dans le registre municipal.";

void main() {
  late InMemoryProjectStore projects;
  late CountingSyncStore sync;
  late InMemoryBookSaleStore sales;
  late InMemoryKdpDatabase kdp;
  late HttpServer server;
  late String baseUrl;

  /// Builds the dependencies of the showcase, with in-memory stores.
  AppDependencies buildDependencies() {
    final List<String> logLines = <String>[];
    return AppDependencies(
      projects: projects,
      sync: sync,
      audit: InMemoryAuditLog(),
      comments: InMemoryCommentStore(),
      purge: InMemoryAccountPurgeStore(entries: const <AuditEntry>[]),
      ai: StubAiGateway(),
      payments: StubPaymentGateway(),
      storage: InMemoryObjectStorage(),
      keyValue: InMemoryKeyValueStore(),
      jwtVerifier: JwtVerifier(
        jwks: StaticJwksProvider(const <String, JsonWebKey>{}),
        expectedIssuer: 'https://project.test/auth/v1',
      ),
      logger: Logger(level: LogLevel.warning, sink: logLines.add),
      databaseProbe: const AlwaysHealthyProbe(),
      syncHub: SyncHub(),
      shutdown: () async {},
      bookSales: sales,
      kdp: kdp,
    );
  }

  /// Starts the showcase on an ephemeral port.
  Future<void> startServer() async {
    final Router router = Router();
    registerPublicationRoutes(router, buildDependencies(), testConfig());
    final List<String> logLines = <String>[];
    final Handler handler = Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning, sink: logLines.add),
          ),
        )
        .addHandler(router.call);
    server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
  }

  /// The operations that publish the chapter of a scene.
  List<SyncOpRecord> chapterOps({
    required String projectId,
    required String docId,
    required (String, String)? chapter,
    required String ownerId,
  }) {
    if (chapter == null) return const <SyncOpRecord>[];
    return <SyncOpRecord>[
      _meta(
        projectId: projectId,
        docId: docId,
        lamport: 10,
        key: 'chapter_id',
        value: chapter.$1,
        authorId: ownerId,
      ),
      _meta(
        projectId: projectId,
        docId: docId,
        lamport: 11,
        key: 'chapter_title',
        value: chapter.$2,
        authorId: ownerId,
      ),
    ];
  }

  /// Creates a project and writes two scenes in its journal.
  Future<String> publishBook({
    ManuscriptStatus status = ManuscriptStatus.published,
    bool isPublic = true,
    String ownerId = 'user-1',
    Map<String, (String, String)> chapters = const <String, (String, String)>{},
  }) async {
    final ProjectRecord created = await projects.create(
      ownerId: ownerId,
      title: bookTitle,
      synopsis: bookSynopsis,
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    final ProjectRecord project = await projects.update(
      created.copyWith(status: status, isPublic: isPublic),
    );

    await sync.append(
      projectId: project.id,
      operations: <SyncOpRecord>[
        _paragraph(
          projectId: project.id,
          docId: 'scene-1',
          lamport: 1,
          blockId: 'block-1',
          orderKey: '5',
          content: firstExcerpt,
          authorId: ownerId,
        ),
        _paragraph(
          projectId: project.id,
          docId: 'scene-1',
          lamport: 2,
          blockId: 'block-2',
          orderKey: '7',
          content: secondParagraph,
          authorId: ownerId,
        ),
        _paragraph(
          projectId: project.id,
          docId: 'scene-2',
          lamport: 3,
          blockId: 'block-3',
          orderKey: '5',
          content: otherExcerpt,
          authorId: ownerId,
        ),
        ...chapterOps(
          projectId: project.id,
          docId: 'scene-1',
          chapter: chapters['scene-1'],
          ownerId: ownerId,
        ),
        ...chapterOps(
          projectId: project.id,
          docId: 'scene-2',
          chapter: chapters['scene-2'],
          ownerId: ownerId,
        ),
      ],
    );
    return project.id;
  }

  /// Publishes the commercial metadata of the book [projectId].
  ///
  /// The metadata comes from the publication the author prepared and from
  /// the sale that puts the book on sale: the page shows what was
  /// published.
  Future<void> publishMetadata(String projectId) async {
    await kdp.recordPublication(
      KdpPublication(
        id: 'publication-$projectId',
        projectId: projectId,
        userId: 'user-1',
        title: bookTitle,
        author: 'Aurélien Sandre',
        description: 'Dans un village de pêcheurs.',
        keywords: const <String>['pêche', 'cendre'],
        categories: const <String>['FICTION / Général'],
        issues: const <KdpIssue>[],
        isbn: '9782491503827',
        language: 'fr-FR',
        publisher: 'Éditions du Nord',
        status: KdpPublicationStatus.ready,
        wordCount: 22,
        pageCount: 12,
        epubKey: 'exports/$projectId/livre.epub',
        pdfKey: 'exports/$projectId/livre.pdf',
        epubBytes: 1024,
        pdfBytes: 2048,
        manuscriptVersion: '1',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
    await sales.save(
      BookSaleRecord(
        projectId: projectId,
        ownerId: 'user-1',
        title: bookTitle,
        priceInCents: 890,
        currency: 'eur',
        status: BookSaleStatus.published,
        authorShare: 9000,
        platformShare: 1000,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 2),
        publishedAt: DateTime.utc(2026, 10, 2),
      ),
    );
  }

  /// The page of the book [projectId], as the server answers it.
  Future<Map<String, Object?>> pageOf(String projectId) async {
    final http.Response response = await http.get(
      Uri.parse('$baseUrl/v1/public/books/$projectId'),
    );
    final Map<String, Object?> envelope =
        jsonDecode(response.body) as Map<String, Object?>;
    return envelope['data']! as Map<String, Object?>;
  }

  setUp(() async {
    projects = InMemoryProjectStore();
    sync = CountingSyncStore(InMemorySyncStore());
    sales = InMemoryBookSaleStore();
    kdp = InMemoryKdpDatabase();
    await startServer();
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('la vitrine publique', () {
    test('sert le livre publié et public sans jeton', () async {
      final String projectId = await publishBook();

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId'),
      );

      expect(response.statusCode, 200);
      final Map<String, Object?> envelope =
          jsonDecode(response.body) as Map<String, Object?>;
      expect(envelope.keys, contains('data'));

      final Map<String, Object?> data =
          envelope['data']! as Map<String, Object?>;
      expect(data['project'], <String, Object?>{
        'id': projectId,
        'title': bookTitle,
        'synopsis': bookSynopsis,
        'language': 'fr-FR',
      });
      expect(data['wordCount'], 22);
    });

    test(
      'publie le premier paragraphe des scènes et jamais leur texte',
      () async {
        final String projectId = await publishBook();

        final http.Response response = await http.get(
          Uri.parse('$baseUrl/v1/public/books/$projectId'),
        );
        final Map<String, Object?> data =
            (jsonDecode(response.body) as Map<String, Object?>)['data']!
                as Map<String, Object?>;

        final List<Object?> chapters = data['chapters']! as List<Object?>;
        expect(chapters, hasLength(1));
        final Map<String, Object?> chapter =
            chapters.single! as Map<String, Object?>;
        final List<Object?> scenes = chapter['scenes']! as List<Object?>;
        expect(scenes, hasLength(2));

        final Map<String, Object?> first =
            scenes.first! as Map<String, Object?>;
        expect(first['id'], 'scene-1');
        expect(first['excerpt'], firstExcerpt);
        expect(first['wordCount'], 16);

        final Map<String, Object?> second =
            scenes.last! as Map<String, Object?>;
        expect(second['id'], 'scene-2');
        expect(second['excerpt'], otherExcerpt);

        expect(response.body, isNot(contains(secondParagraph)));
      },
    );

    test(
      'ne divulgue ni le propriétaire, ni les membres, ni les opérations',
      () async {
        final String projectId = await publishBook();

        final http.Response response = await http.get(
          Uri.parse('$baseUrl/v1/public/books/$projectId'),
        );

        expect(response.body, isNot(contains('user-1')));
        expect(response.body, isNot(contains('owner_id')));
        expect(response.body, isNot(contains('author_id')));
        expect(response.body, isNot(contains('members')));
        expect(response.body, isNot(contains('is_public')));
        expect(response.body, isNot(contains('block-1')));
      },
    );

    test('répond 404 quand le projet n’existe pas', () async {
      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/inconnu'),
      );

      expect(response.statusCode, 404);
      final Map<String, Object?> error =
          (jsonDecode(response.body) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'not_found');
    });

    test('répond 404 quand le projet n’est pas publié', () async {
      final String projectId = await publishBook(
        status: ManuscriptStatus.draft,
      );

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId'),
      );

      expect(response.statusCode, 404);
    });

    test('répond 404 quand le projet n’est pas public', () async {
      final String projectId = await publishBook(isPublic: false);

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId'),
      );

      expect(response.statusCode, 404);
    });

    test('ne lit pas le journal d’un livre privé', () async {
      final String projectId = await publishBook(isPublic: false);

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId'),
      );

      expect(response.statusCode, 404);
      expect(
        sync.allCalls,
        0,
        reason: 'le manuscrit d\'un livre privé ne doit jamais être chargé',
      );
    });

    test(
      'répond la même chose pour un projet absent, non publié et privé',
      () async {
        final String draft = await publishBook(
          status: ManuscriptStatus.draft,
          ownerId: 'user-2',
        );
        final String priv = await publishBook(
          isPublic: false,
          ownerId: 'user-3',
        );

        final http.Response absent = await http.get(
          Uri.parse('$baseUrl/v1/public/books/absent'),
        );
        final http.Response unpublished = await http.get(
          Uri.parse('$baseUrl/v1/public/books/$draft'),
        );
        final http.Response private = await http.get(
          Uri.parse('$baseUrl/v1/public/books/$priv'),
        );

        expect(absent.statusCode, 404);
        expect(unpublished.statusCode, 404);
        expect(private.statusCode, 404);
        expect(absent.body, unpublished.body);
        expect(absent.body, private.body);
      },
    );

    test('limite le débit des appels venus de la même adresse', () async {
      final String projectId = await publishBook();

      final List<int> statuses = <int>[];
      http.Response? limited;
      for (var call = 0; call < publicBookRateLimitCapacity + 20; call++) {
        final http.Response response = await http.get(
          Uri.parse('$baseUrl/v1/public/books/$projectId'),
        );
        statuses.add(response.statusCode);
        if (response.statusCode == 429 && limited == null) {
          limited = response;
        }
      }

      expect(statuses.first, 200);
      expect(limited, isNotNull);
      final Map<String, Object?> error =
          (jsonDecode(limited!.body) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'rate_limited');
    });
  });

  group('la couverture, les chapitres et les métadonnées', () {
    test('la page porte l’adresse relative de la couverture', () async {
      final String projectId = await publishBook();

      final Map<String, Object?> data = await pageOf(projectId);

      final Map<String, Object?> cover = data['cover']! as Map<String, Object?>;
      expect(cover['url'], '/v1/public/books/$projectId/cover');
      expect(
        cover['url'],
        isNot(contains('storage.test')),
        reason: 'la réponse publique ne porte jamais une adresse de stockage',
      );
    });

    test('la route de couverture sert le SVG du livre', () async {
      final String projectId = await publishBook();

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId/cover'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('image/svg+xml'));
      expect(response.body, contains(bookTitle));
    });

    test('la route de couverture répond 404 pour un livre privé', () async {
      final String projectId = await publishBook(isPublic: false);

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId/cover'),
      );

      expect(response.statusCode, 404);
    });

    test('la page montre les chapitres du livre', () async {
      final String projectId = await publishBook(
        chapters: <String, (String, String)>{
          'scene-1': ('chapter-1', 'Le sel'),
          'scene-2': ('chapter-2', 'La cloche de Saint-Mérien'),
        },
      );

      final Map<String, Object?> data = await pageOf(projectId);

      final List<Object?> chapters = data['chapters']! as List<Object?>;
      expect(chapters, hasLength(2));

      final Map<String, Object?> first =
          chapters.first! as Map<String, Object?>;
      expect(first['id'], 'chapter-1');
      expect(first['title'], 'Le sel');
      expect(first['scenes'], hasLength(1));

      final Map<String, Object?> second =
          chapters.last! as Map<String, Object?>;
      expect(second['id'], 'chapter-2');
      expect(second['title'], 'La cloche de Saint-Mérien');
    });

    test('la page porte les métadonnées publiées', () async {
      final String projectId = await publishBook();
      await publishMetadata(projectId);

      final Map<String, Object?> data = await pageOf(projectId);

      final Map<String, Object?> metadata =
          data['metadata']! as Map<String, Object?>;
      expect(metadata['isbn'], '9782491503827');
      expect(metadata['publisher'], 'Éditions du Nord');
      expect(metadata['language'], 'fr-FR');
      expect(metadata['contributors'], <String>['Aurélien Sandre']);
      expect(metadata['categories'], <String>['FICTION / Général']);
      expect(metadata['price'], <String, Object?>{
        'amount': 890,
        'currency': 'eur',
      });
      expect(metadata['publishedAt'], '2026-10-02T00:00:00.000Z');
      expect(metadata.containsKey('user_id'), isFalse);
    });

    test(
      'la page ne porte aucune métadonnée quand le livre n’en a pas',
      () async {
        final String projectId = await publishBook();

        final Map<String, Object?> data = await pageOf(projectId);

        expect(data.containsKey('metadata'), isFalse);
      },
    );

    test('la page ne divulgue pas le compte de l’auteur', () async {
      final String projectId = await publishBook();
      await publishMetadata(projectId);

      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/public/books/$projectId'),
      );

      expect(response.body, isNot(contains('user-1')));
      expect(response.body, isNot(contains('owner_id')));
    });
  });

  group('l’extrait d’une scène', () {
    test('est le premier paragraphe de la scène', () async {
      final CrdtDocument document = _documentOf(<String>[
        'Premier paragraphe.',
        'Second paragraphe.',
      ]);

      expect(excerptOf(document), 'Premier paragraphe.');
    });

    test('est vide quand la scène n’a jamais été écrite', () {
      expect(excerptOf(CrdtDocument.empty(DocumentId('vide'))), isEmpty);
    });

    test('est coupé sur une frontière de mot', () {
      final String long = List<String>.filled(120, 'Mot').join(' ');

      final String excerpt = truncateExcerpt(long);

      expect(excerpt.length, lessThanOrEqualTo(maxExcerptLength + 1));
      expect(excerpt, endsWith('Mot$excerptEllipsis'));
    });
  });
}

/// A journal that counts the reads of a whole project.
///
/// The showcase must prove that a private book is never read: the counter
/// tells whether the manuscript of a private project was loaded.
final class CountingSyncStore implements SyncStore {
  /// Creates a journal counting the reads of [delegate].
  CountingSyncStore(this._delegate);

  final SyncStore _delegate;

  /// The number of times the whole journal of a project was read.
  int allCalls = 0;

  @override
  Future<List<SyncOpRecord>> all({required String projectId}) {
    allCalls += 1;
    return _delegate.all(projectId: projectId);
  }

  @override
  Future<AppendResult> append({
    required String projectId,
    required List<SyncOpRecord> operations,
  }) {
    return _delegate.append(projectId: projectId, operations: operations);
  }

  @override
  Future<List<SyncOpRecord>> since({
    required String projectId,
    required int lamport,
    required int limit,
  }) {
    return _delegate.since(
      projectId: projectId,
      lamport: lamport,
      limit: limit,
    );
  }

  @override
  Future<Set<String>> projectsOfDocument(String docId) {
    return _delegate.projectsOfDocument(docId);
  }
}

/// Builds the operation that inserts a paragraph in a document.
SyncOpRecord _paragraph({
  required String projectId,
  required String docId,
  required int lamport,
  required String blockId,
  required String orderKey,
  required String content,
  required String authorId,
}) {
  return SyncOpRecord(
    opId: 'op-$lamport',
    projectId: projectId,
    docId: docId,
    lamport: lamport,
    authorId: authorId,
    type: 'insertBlock',
    payload: <String, dynamic>{
      'block_id': blockId,
      'parent_id': null,
      'order_key': orderKey,
      'type': 'paragraph',
      'content': content,
    },
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );
}

/// Builds the operation that writes a metadata of a document.
SyncOpRecord _meta({
  required String projectId,
  required String docId,
  required int lamport,
  required String key,
  required String value,
  required String authorId,
}) {
  return SyncOpRecord(
    opId: 'meta-$lamport',
    projectId: projectId,
    docId: docId,
    lamport: lamport,
    authorId: authorId,
    type: 'setMeta',
    payload: <String, dynamic>{'key': key, 'value': value},
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );
}

/// Builds a document holding one paragraph per given text.
CrdtDocument _documentOf(List<String> paragraphs) {
  final DocumentId id = DocumentId('document-test');
  CrdtDocument document = CrdtDocument.empty(id);
  var lamport = 0;
  for (final String paragraph in paragraphs) {
    lamport += 1;
    document = document.apply(
      InsertBlockOp(
        doc: id,
        lamport: lamport,
        author: const AuthorId('test-author'),
        blockId: BlockId('block-$lamport'),
        parent: null,
        order: OrderKey('$lamport'),
        type: BlockType.paragraph,
        content: TextContent(paragraph),
      ),
    );
  }
  return document;
}
