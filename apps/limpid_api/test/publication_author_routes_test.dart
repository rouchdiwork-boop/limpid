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

/// L'identifiant de l'auteur des livres publiés.
const String authorId = 'auteur-1';

/// Le titre du premier livre publié.
const String firstTitle = 'Les Heures de Cendre';

/// Le résumé du premier livre publié.
const String firstSynopsis =
    'Dans un village de pêcheurs qui ne compte plus ses morts.';

/// Le titre du second livre publié.
const String secondTitle = 'Carnets de dune';

/// Le résumé du second livre publié.
const String secondSynopsis = 'Les carnets que le vent emporte sous les dunes.';

/// Le titre du livre privé, qui ne doit jamais apparaître.
const String privateTitle = 'Le cahier fermé';

/// Le texte de la scène du livre privé, qui ne doit jamais sortir.
const String privateExcerpt = 'Ce texte ne doit jamais quitter le serveur.';

/// Le nombre de mots de la première scène du premier livre.
const int firstSceneWords = 7;

/// Le nombre de mots de la seconde scène du premier livre.
const int secondSceneWords = 6;

/// Le nombre de mots de la scène du second livre.
const int otherSceneWords = 9;

void main() {
  late InMemoryProjectStore projects;
  late CountingSyncStore sync;
  late InMemoryBookSaleStore sales;
  late HttpServer server;
  late String baseUrl;

  /// Construit les dépendances de la vitrine, avec des magasins en mémoire.
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
    );
  }

  /// Démarre la vitrine sur un port éphémère.
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

  /// Crée un livre et écrit ses scènes dans le journal.
  Future<String> publishBook({
    required String title,
    required String synopsis,
    List<String> scenes = const <String>[],
    ManuscriptStatus status = ManuscriptStatus.published,
    bool isPublic = true,
    String owner = authorId,
  }) async {
    final ProjectRecord created = await projects.create(
      ownerId: owner,
      title: title,
      synopsis: synopsis,
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    final ProjectRecord project = await projects.update(
      created.copyWith(status: status, isPublic: isPublic),
    );

    final List<SyncOpRecord> operations = <SyncOpRecord>[];
    for (int index = 0; index < scenes.length; index++) {
      operations.add(
        _paragraph(
          projectId: project.id,
          docId: 'scene-$index',
          lamport: index + 1,
          blockId: 'block-$index',
          content: scenes[index],
          authorId: owner,
        ),
      );
    }
    if (operations.isNotEmpty) {
      await sync.append(projectId: project.id, operations: operations);
    }
    return project.id;
  }

  /// Demande la page d'un auteur.
  Future<http.Response> pageOf(String id) {
    return http.get(Uri.parse('$baseUrl/v1/public/authors/$id'));
  }

  /// Les livres de la réponse d'un auteur.
  List<Map<String, Object?>> booksOf(http.Response response) {
    final Map<String, Object?> envelope =
        jsonDecode(response.body) as Map<String, Object?>;
    final Map<String, Object?> data = envelope['data']! as Map<String, Object?>;
    final List<Object?> books = data['books']! as List<Object?>;
    return books
        .map((Object? book) => book! as Map<String, Object?>)
        .toList(growable: false);
  }

  /// Met un livre en vente, à la date [publishedAt].
  ///
  /// La mise en vente est l'acte qui publie le livre : c'est sa date qui
  /// place le livre sur la page de l'auteur.
  Future<void> putOnSale(
    String projectId, {
    required DateTime publishedAt,
    String owner = authorId,
  }) async {
    await sales.save(
      BookSaleRecord(
        projectId: projectId,
        ownerId: owner,
        title: 'Un livre',
        priceInCents: 890,
        currency: 'eur',
        status: BookSaleStatus.published,
        authorShare: 9000,
        platformShare: 1000,
        createdAt: publishedAt,
        updatedAt: publishedAt,
        publishedAt: publishedAt,
      ),
    );
  }

  setUp(() async {
    projects = InMemoryProjectStore();
    sync = CountingSyncStore(InMemorySyncStore());
    sales = InMemoryBookSaleStore();
    await startServer();
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('la vitrine d’un auteur', () {
    test('sert les livres publiés et publics sans jeton', () async {
      final String first = await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
        scenes: <String>[
          'La cloche sonna à quatre heures douze.',
          "C'était écrit dans le registre municipal.",
        ],
      );
      final String second = await publishBook(
        title: secondTitle,
        synopsis: secondSynopsis,
        scenes: <String>['Le sel avait formé sur les vitres une croûte.'],
      );

      final http.Response response = await pageOf(authorId);

      expect(response.statusCode, 200);
      final List<Map<String, Object?>> books = booksOf(response);
      expect(books, hasLength(2));

      final Map<String, Object?> published = books.firstWhere(
        (Map<String, Object?> book) => book['id'] == first,
      );
      expect(published['title'], firstTitle);
      expect(published['synopsis'], firstSynopsis);
      expect(published['wordCount'], firstSceneWords + secondSceneWords);
      expect(
        published.keys,
        unorderedEquals(<String>[
          'id',
          'title',
          'synopsis',
          'wordCount',
          'coverUrl',
        ]),
      );

      final Map<String, Object?> other = books.firstWhere(
        (Map<String, Object?> book) => book['id'] == second,
      );
      expect(other['title'], secondTitle);
      expect(other['synopsis'], secondSynopsis);
      expect(other['wordCount'], otherSceneWords);
    });

    test('laisse le livre privé hors de la liste', () async {
      await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
        scenes: <String>['La cloche sonna à quatre heures douze.'],
      );
      await publishBook(
        title: privateTitle,
        synopsis: 'Un cahier que personne ne doit lire.',
        scenes: <String>[privateExcerpt],
        isPublic: false,
      );
      await publishBook(
        title: 'Un brouillon',
        synopsis: 'Un manuscrit qui n’est pas fini.',
        scenes: <String>['Le premier jet, jamais publié.'],
        status: ManuscriptStatus.draft,
      );

      final http.Response response = await pageOf(authorId);

      expect(response.statusCode, 200);
      final List<Map<String, Object?>> books = booksOf(response);
      expect(books, hasLength(1));
      expect(books.single['title'], firstTitle);
      expect(response.body, isNot(contains(privateTitle)));
      expect(response.body, isNot(contains(privateExcerpt)));
    });

    test('ne lit pas le journal d’un livre privé', () async {
      await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
        scenes: <String>['La cloche sonna à quatre heures douze.'],
      );
      final String private = await publishBook(
        title: privateTitle,
        synopsis: 'Un cahier que personne ne doit lire.',
        scenes: <String>[privateExcerpt],
        isPublic: false,
      );

      final http.Response response = await pageOf(authorId);

      expect(response.statusCode, 200);
      expect(
        sync.allCallsOf(private),
        0,
        reason: 'le manuscrit d\'un livre privé ne doit jamais être chargé',
      );
      expect(sync.allCalls, 1);
    });

    test(
      'ne divulgue ni le propriétaire, ni les membres, ni le texte',
      () async {
        await publishBook(
          title: firstTitle,
          synopsis: firstSynopsis,
          scenes: <String>['La cloche sonna à quatre heures douze.'],
        );

        final http.Response response = await pageOf(authorId);

        expect(response.body, isNot(contains('owner_id')));
        expect(response.body, isNot(contains(authorId)));
        expect(response.body, isNot(contains('is_public')));
        expect(response.body, isNot(contains('members')));
        expect(response.body, isNot(contains('La cloche sonna')));
      },
    );

    test('répond 404 quand l’auteur n’existe pas', () async {
      final http.Response response = await pageOf('inconnu');

      expect(response.statusCode, 404);
      final Map<String, Object?> error =
          (jsonDecode(response.body) as Map<String, Object?>)['error']!
              as Map<String, Object?>;
      expect(error['code'], 'not_found');
    });

    test(
      'répond la même chose pour un auteur absent et pour un auteur sans livre',
      () async {
        await publishBook(
          title: privateTitle,
          synopsis: 'Un cahier que personne ne doit lire.',
          scenes: <String>[privateExcerpt],
          isPublic: false,
        );

        final http.Response absent = await pageOf('inconnu');
        final http.Response withoutBook = await pageOf(authorId);

        expect(absent.statusCode, 404);
        expect(withoutBook.statusCode, 404);
        expect(absent.body, withoutBook.body);
      },
    );

    test('limite le débit des appels venus de la même adresse', () async {
      await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
        scenes: <String>['La cloche sonna à quatre heures douze.'],
      );

      final List<int> statuses = <int>[];
      http.Response? limited;
      for (var call = 0; call < publicAuthorRateLimitCapacity + 20; call++) {
        final http.Response response = await pageOf(authorId);
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

  group('l’ordre des livres de l’auteur', () {
    test('liste les livres du plus récemment publié au plus ancien', () async {
      final String older = await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
      );
      final String newer = await publishBook(
        title: secondTitle,
        synopsis: secondSynopsis,
      );
      await putOnSale(older, publishedAt: DateTime.utc(2026, 3, 1));
      await putOnSale(newer, publishedAt: DateTime.utc(2026, 6, 1));

      final http.Response response = await pageOf(authorId);

      final List<Map<String, Object?>> books = booksOf(response);
      expect(books.map((Map<String, Object?> book) => book['id']), <String>[
        newer,
        older,
      ]);
      expect(books.first['publishedAt'], '2026-06-01T00:00:00.000Z');
    });

    test('place un livre jamais vendu après les autres', () async {
      final String sold = await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
      );
      final String unsold = await publishBook(
        title: secondTitle,
        synopsis: secondSynopsis,
      );
      await putOnSale(sold, publishedAt: DateTime.utc(2026, 3, 1));

      final http.Response response = await pageOf(authorId);

      final List<Map<String, Object?>> books = booksOf(response);
      expect(books.map((Map<String, Object?> book) => book['id']), <String>[
        sold,
        unsold,
      ]);
      expect(books.last.containsKey('publishedAt'), isFalse);
    });

    test('la modification d’un livre ne change pas l’ordre', () async {
      final String older = await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
      );
      final String newer = await publishBook(
        title: secondTitle,
        synopsis: secondSynopsis,
      );
      await putOnSale(older, publishedAt: DateTime.utc(2026, 3, 1));
      await putOnSale(newer, publishedAt: DateTime.utc(2026, 6, 1));

      final ProjectAccess access = (await projects.access(
        projectId: older,
        userId: authorId,
      ))!;
      await projects.update(access.project.copyWith(title: 'Titre corrigé'));

      final http.Response response = await pageOf(authorId);

      final List<Map<String, Object?>> books = booksOf(response);
      expect(books.map((Map<String, Object?> book) => book['id']), <String>[
        newer,
        older,
      ]);
    });

    test('porte l’adresse de la couverture de chaque livre', () async {
      final String book = await publishBook(
        title: firstTitle,
        synopsis: firstSynopsis,
      );

      final http.Response response = await pageOf(authorId);

      final List<Map<String, Object?>> books = booksOf(response);
      expect(books.single['coverUrl'], '/v1/public/books/$book/cover');
    });
  });
}

/// Un journal qui compte les lectures de chaque projet.
///
/// La vitrine doit prouver qu'un livre privé n'est jamais lu : le compteur
/// dit si le manuscrit d'un projet a été chargé.
final class CountingSyncStore implements SyncStore {
  /// Crée un journal comptant les lectures de [delegate].
  CountingSyncStore(this._delegate);

  final SyncStore _delegate;

  /// Le nombre de fois que le journal d'un projet a été lu.
  final Map<String, int> allCallsByProject = <String, int>{};

  /// Le nombre total de lectures de journaux.
  int get allCalls => allCallsByProject.values.fold<int>(
    0,
    (int sum, int count) => sum + count,
  );

  /// Le nombre de fois que le journal du projet a été lu.
  int allCallsOf(String projectId) => allCallsByProject[projectId] ?? 0;

  @override
  Future<List<SyncOpRecord>> all({required String projectId}) {
    allCallsByProject[projectId] = allCallsOf(projectId) + 1;
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
  required String content,
  required String authorId,
}) {
  return SyncOpRecord(
    opId: 'op-$projectId-$lamport',
    projectId: projectId,
    docId: docId,
    lamport: lamport,
    authorId: authorId,
    type: 'insertBlock',
    payload: <String, dynamic>{
      'block_id': blockId,
      'parent_id': null,
      'order_key': '5',
      'type': 'paragraph',
      'content': content,
    },
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );
}
