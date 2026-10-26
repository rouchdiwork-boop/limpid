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

void main() {
  group('API publique', () {
    late _Harness harness;

    setUp(() async {
      harness = await _Harness.start();
    });

    tearDown(() async {
      await harness.stop();
    });

    group('les ressources du compte', () {
      late String key;
      late String projectId;

      setUp(() async {
        await harness.givePlan('user-studio', SubscriptionPlan.studio);
        key = await harness.createKey('user-studio');
        projectId = await harness.createProject('user-studio', 'Le livre');
        await harness.writeScene(projectId);
      });

      test('une clé Studio liste les projets du compte', () async {
        final http.Response response = await harness.get(
          '/v1/api/projects',
          apiKey: key,
        );

        expect(response.statusCode, 200);
        final List<dynamic> items = _itemsOf(response);
        expect(items, hasLength(1));
        final Map<String, dynamic> project =
            items.first! as Map<String, dynamic>;
        expect(project['id'], projectId);
        expect(project['title'], 'Le livre');
        expect(project['status'], 'draft');
        expect(_metaOf(response)['total'], 1);
      });

      test(
        'une clé Studio lit un projet avec ses chapitres et ses scènes',
        () async {
          // Le projet est un brouillon : la clé du compte lit le manuscrit
          // de son propre compte, l'API n'est pas la vitrine publique.
          final http.Response response = await harness.get(
            '/v1/api/projects/$projectId',
            apiKey: key,
          );

          expect(response.statusCode, 200);
          final Map<String, dynamic> data = _dataOf(response);
          expect(data['id'], projectId);
          expect(data['title'], 'Le livre');

          final List<dynamic> chapters = data['chapters']! as List<dynamic>;
          expect(chapters, hasLength(1));
          final Map<String, dynamic> chapter =
              chapters.first! as Map<String, dynamic>;
          expect(chapter['id'], 'doc-1');
          expect(chapter['title'], 'La première scène');
          expect(chapter['order'], 0);

          final List<dynamic> scenes = chapter['scenes']! as List<dynamic>;
          expect(scenes, hasLength(1));
          final Map<String, dynamic> scene =
              scenes.first! as Map<String, dynamic>;
          expect(scene['doc_id'], 'doc-1');
          expect(scene['title'], 'La première scène');
          expect(scene['word_count'], 5);
          expect(scene['block_count'], 1);
        },
      );

      test('les scènes qui déclarent un chapitre se regroupent', () async {
        final String id = await harness.createProject(
          'user-studio',
          'Les chapitres',
        );
        await harness.writeScene(
          id,
          docId: 'doc-a',
          title: 'Scène A',
          chapterId: 'chapitre-1',
          chapterTitle: 'Le premier chapitre',
        );
        await harness.writeScene(
          id,
          docId: 'doc-b',
          title: 'Scène B',
          chapterId: 'chapitre-1',
          chapterTitle: 'Le premier chapitre',
        );

        final http.Response response = await harness.get(
          '/v1/api/projects/$id',
          apiKey: key,
        );
        expect(response.statusCode, 200);

        final List<dynamic> chapters =
            _dataOf(response)['chapters']! as List<dynamic>;
        expect(chapters, hasLength(1));
        final Map<String, dynamic> chapter =
            chapters.first! as Map<String, dynamic>;
        expect(chapter['id'], 'chapitre-1');
        expect(chapter['title'], 'Le premier chapitre');

        final List<dynamic> scenes = chapter['scenes']! as List<dynamic>;
        expect(scenes, hasLength(2));
        expect((scenes.first! as Map<String, dynamic>)['doc_id'], 'doc-a');
        expect((scenes.last! as Map<String, dynamic>)['doc_id'], 'doc-b');
      });

      test("l'arbre a la forme de la synchronisation", () async {
        final http.Response sessionTree = await harness.sessionGet(
          '/v1/projects/$projectId/tree',
          'user-studio',
        );
        expect(sessionTree.statusCode, 200);

        final http.Response publicTree = await harness.get(
          '/v1/api/projects/$projectId/tree',
          apiKey: key,
        );
        expect(publicTree.statusCode, 200);

        // L'API publique rend exactement ce que rend la synchronisation.
        expect(jsonDecode(publicTree.body), jsonDecode(sessionTree.body));

        final List<dynamic> trees = _dataListOf(publicTree);
        expect(trees, hasLength(1));
        final Map<String, dynamic> tree = trees.first! as Map<String, dynamic>;
        expect(tree['doc_id'], 'doc-1');
        expect(
          tree.keys,
          containsAll(<String>[
            'doc_id',
            'lamport',
            'meta',
            'operation_count',
            'blocks',
          ]),
        );

        final List<dynamic> blocks = tree['blocks']! as List<dynamic>;
        final Map<String, dynamic> block =
            blocks.first! as Map<String, dynamic>;
        expect(block['content'], 'Il pleuvait sur la falaise.');
        expect(
          block.keys,
          containsAll(<String>[
            'id',
            'parent_id',
            'order_key',
            'type',
            'content',
            'lamport',
            'author_id',
            'deleted',
            'version',
            'marks',
            'children',
          ]),
        );
      });

      test("un projet d'un autre compte est absent", () async {
        final String otherId = await harness.createProject(
          'user-other',
          "Le livre d'un autre",
        );

        final http.Response response = await harness.get(
          '/v1/api/projects/$otherId',
          apiKey: key,
        );
        expect(response.statusCode, 404);
        expect(_errorOf(response)['code'], 'not_found');
        expect(response.body, isNot(contains("Le livre d'un autre")));

        final http.Response tree = await harness.get(
          '/v1/api/projects/$otherId/tree',
          apiKey: key,
        );
        expect(tree.statusCode, 404);
        expect(tree.body, isNot(contains('Il pleuvait')));

        // Le projet d'un autre compte n'apparaît pas non plus dans la liste.
        final http.Response listed = await harness.get(
          '/v1/api/projects',
          apiKey: key,
        );
        expect(
          _itemsOf(
            listed,
          ).map((dynamic item) => (item! as Map<String, dynamic>)['id']),
          isNot(contains(otherId)),
        );
      });

      test('les réponses ne portent jamais le secret de la clé', () async {
        for (final String path in <String>[
          '/v1/api/me',
          '/v1/api/events',
          '/v1/api/projects',
          '/v1/api/projects/$projectId',
          '/v1/api/projects/$projectId/tree',
        ]) {
          final http.Response response = await harness.get(path, apiKey: key);
          expect(response.statusCode, 200, reason: path);
          expect(response.body, isNot(contains(key)), reason: path);
        }
      });
    });

    group('le garde-fou de la formule', () {
      test('un compte hors Studio est refusé sur toutes les routes', () async {
        // La route des clés refuse un compte gratuit : la clé est créée par
        // le service, pour éprouver le garde-fou sur l'API elle-même.
        final String freeKey = await harness.mintKey('user-free');

        for (final String path in <String>[
          '/v1/api/me',
          '/v1/api/events',
          '/v1/api/projects',
          '/v1/api/projects/projet-1',
          '/v1/api/projects/projet-1/tree',
        ]) {
          final http.Response response = await harness.get(
            path,
            apiKey: freeKey,
          );
          expect(response.statusCode, 403, reason: path);
          final Map<String, dynamic> error = _errorOf(response);
          expect(error['code'], 'forbidden', reason: path);
          expect(
            (error['details']! as Map<String, dynamic>)['feature'],
            'api_and_webhooks',
            reason: path,
          );
        }
      });
    });

    group('le périmètre de la clé', () {
      test('une clé sans le périmètre de lecture est refusée', () async {
        await harness.givePlan('user-studio', SubscriptionPlan.studio);
        final String key = await harness.mintKey(
          'user-studio',
          scopes: <ApiKeyScope>{ApiKeyScope.write},
        );

        for (final String path in <String>[
          '/v1/api/me',
          '/v1/api/events',
          '/v1/api/projects',
        ]) {
          final http.Response response = await harness.get(path, apiKey: key);
          expect(response.statusCode, 403, reason: path);
          expect(
            (_errorOf(response)['details']! as Map<String, dynamic>)['scope'],
            'read',
            reason: path,
          );
        }
      });
    });

    group("l'identification", () {
      test(
        'une clé absente, mal formée ou un jeton de session sont refusés',
        () async {
          final http.Response missing = await harness.get('/v1/api/me');
          expect(missing.statusCode, 401);
          expect(
            (_errorOf(missing)['details']! as Map<String, dynamic>)['reason'],
            'missing_api_key',
          );

          final http.Response malformed = await harness.get(
            '/v1/api/me',
            apiKey: 'pas-une-cle',
          );
          expect(malformed.statusCode, 401);
          expect(
            (_errorOf(malformed)['details']! as Map<String, dynamic>)['reason'],
            'unknown_api_key',
          );

          // Le jeton de session n'ouvre pas l'API publique : cette surface est
          // celle de la clé d'API.
          await harness.givePlan('user-studio', SubscriptionPlan.studio);
          final http.Response withToken = await harness.get(
            '/v1/api/me',
            headers: await harness.sessionOf('user-studio'),
          );
          expect(withToken.statusCode, 401);
          expect(
            (_errorOf(withToken)['details']! as Map<String, dynamic>)['reason'],
            'missing_api_key',
          );
        },
      );
    });
  });
}

/// L'API de la suite de tests : la session et l'API publique.
///
/// Les deux serveurs partagent les mêmes dépendances : un projet écrit par
/// la session se lit par la clé d'API, et l'arbre public se compare à
/// l'arbre de la synchronisation.
final class _Harness {
  _Harness({required this.session, required this.publicApi});

  /// L'API de session, avec ses jetons et ses formules.
  final TestServer session;

  /// L'API publique, authentifiée par la clé d'API.
  final HttpServer publicApi;

  /// La base de l'API publique.
  String get baseUrl => 'http://127.0.0.1:${publicApi.port}';

  /// Les en-têtes de session du compte [userId], par compte.
  final Map<String, Map<String, String>> _sessions =
      <String, Map<String, String>>{};

  /// Démarre les deux serveurs.
  static Future<_Harness> start() async {
    final TestServer session = await startTestServer();
    final AppConfig config = testConfig();
    final Router router = Router();
    registerPublicApiRoutes(
      router,
      config,
      projects: session.dependencies.projects,
      sync: session.dependencies.sync,
      webhooks: session.dependencies.webhooks!,
      planOf: session.dependencies.planOf,
    );

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning),
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(
          authenticationMiddleware(
            verifier: session.dependencies.jwtVerifier,
            // L'API publique s'authentifie par sa clé : elle passe devant le
            // jeton de session.
            exemptPrefixes: <String>[...publicPathPrefixes, '/v1/api/'],
          ),
        )
        .addHandler(router.call);

    final HttpServer server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      0,
    );
    return _Harness(session: session, publicApi: server);
  }

  /// La formule du compte [userId].
  Future<void> givePlan(String userId, SubscriptionPlan plan) {
    return session.givePlan(userId, plan);
  }

  /// Les en-têtes de session du compte [userId].
  ///
  /// La formule Studio exige la double authentification : la preuve est
  /// demandée avant tout appel de session.
  Future<Map<String, String>> sessionOf(String userId) async {
    final Map<String, String>? known = _sessions[userId];
    if (known != null) return known;
    final String proof = await session.enableTwoFactor(userId);
    final Map<String, String> headers = <String, String>{
      'authorization': 'Bearer ${session.tokenFor(userId)}',
      twoFactorProofHeader: proof,
    };
    _sessions[userId] = headers;
    return headers;
  }

  /// Crée une clé d'API par la session et renvoie son secret.
  Future<String> createKey(
    String userId, {
    Set<ApiKeyScope> scopes = const <ApiKeyScope>{ApiKeyScope.read},
  }) async {
    final http.Response response = await session.post(
      '/v1/api-keys',
      headers: await sessionOf(userId),
      body: <String, Object?>{
        'name': 'Intégration',
        'scopes': scopes
            .map((ApiKeyScope scope) => scope.key)
            .toList(growable: false),
      },
    );
    expect(response.statusCode, 201);
    return _dataOf(response)['secret']! as String;
  }

  /// Crée une clé d'API sans passer par la route.
  ///
  /// La route `/v1/api-keys` refuse un compte hors Studio : la clé d'un
  /// compte gratuit se crée par le service, pour éprouver le garde-fou de la
  /// formule sur l'API publique elle-même.
  Future<String> mintKey(
    String userId, {
    Set<ApiKeyScope> scopes = const <ApiKeyScope>{ApiKeyScope.read},
  }) async {
    final ApiKeyService service = ApiKeyService(
      database: session.dependencies.webhooks!,
    );
    final CreatedApiKey created = await service.create(
      userId: userId,
      name: 'Intégration',
      scopes: scopes,
    );
    return created.secret;
  }

  /// Crée un projet par la session et renvoie son identifiant.
  Future<String> createProject(String userId, String title) async {
    final http.Response response = await session.post(
      '/v1/projects',
      headers: await sessionOf(userId),
      body: <String, Object?>{'title': title},
    );
    expect(response.statusCode, 201);
    return _dataOf(response)['id']! as String;
  }

  /// Écrit une scène dans le projet [projectId], par la synchronisation.
  ///
  /// La scène porte son titre et, quand la scène [chapterId] est donnée, le
  /// chapitre auquel elle appartient.
  Future<void> writeScene(
    String projectId, {
    String userId = 'user-studio',
    String docId = 'doc-1',
    String title = 'La première scène',
    String? chapterId,
    String? chapterTitle,
    String content = 'Il pleuvait sur la falaise.',
  }) async {
    final List<Map<String, Object?>> operations = <Map<String, Object?>>[
      _metaOperation(
        docId: docId,
        lamport: 1,
        authorId: userId,
        key: 'title',
        value: title,
      ),
      if (chapterId != null)
        _metaOperation(
          docId: docId,
          lamport: 2,
          authorId: userId,
          key: 'chapter_id',
          value: chapterId,
        ),
      if (chapterTitle != null)
        _metaOperation(
          docId: docId,
          lamport: 3,
          authorId: userId,
          key: 'chapter_title',
          value: chapterTitle,
        ),
      <String, Object?>{
        'op_id': 'op-block-$docId',
        'doc_id': docId,
        'lamport': 9,
        'author_id': userId,
        'type': 'insertBlock',
        'payload': <String, Object?>{
          'block_id': 'block-1',
          'parent_id': null,
          'order_key': '5',
          'type': 'paragraph',
          'content': content,
        },
      },
    ];

    final http.Response response = await session.post(
      '/v1/projects/$projectId/ops',
      headers: await sessionOf(userId),
      body: <String, Object?>{'operations': operations},
    );
    expect(response.statusCode, 200);
  }

  /// Un GET sur l'API publique.
  Future<http.Response> get(
    String path, {
    String? apiKey,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: _withKey(apiKey, headers),
    );
  }

  /// Un GET sur l'API de session.
  Future<http.Response> sessionGet(String path, String userId) async {
    return session.get(path, headers: await sessionOf(userId));
  }

  /// Arrête les deux serveurs.
  Future<void> stop() async {
    await publicApi.close(force: true);
    await session.stop();
  }
}

/// Une opération qui fixe une métadonnée du document.
Map<String, Object?> _metaOperation({
  required String docId,
  required int lamport,
  required String authorId,
  required String key,
  required String value,
}) {
  return <String, Object?>{
    'op_id': 'op-$docId-$lamport',
    'doc_id': docId,
    'lamport': lamport,
    'author_id': authorId,
    'type': 'setMeta',
    'payload': <String, Object?>{'key': key, 'value': value},
  };
}

/// Les en-têtes d'un appel, la clé d'API comprise.
///
/// La clé d'API est absente des en-têtes quand elle n'est pas fournie : la
/// surface publique se prouve par la clé, jamais par le jeton de session.
Map<String, String> _withKey(String? apiKey, Map<String, String> headers) {
  if (apiKey == null) return headers;
  return <String, String>{...headers, apiKeyHeader: apiKey};
}

/// Les données d'une réponse réussie.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as Map<String, dynamic>;
}

/// La liste des données d'une réponse réussie.
List<dynamic> _dataListOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as List<dynamic>;
}

/// Les éléments d'une réponse paginée.
List<dynamic> _itemsOf(http.Response response) => _dataListOf(response);

/// Les métadonnées d'une réponse paginée.
Map<String, dynamic> _metaOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['meta']! as Map<String, dynamic>;
}

/// L'erreur d'une réponse en échec.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error']! as Map<String, dynamic>;
}
