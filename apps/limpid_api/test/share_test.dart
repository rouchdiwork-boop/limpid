import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/db/sqlite_share_store.dart';
import 'package:limpid_api/src/routes/sync_routes.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  group('partages en lecture', () {
    late _Harness harness;
    late Map<String, String> auth;
    late String projectId;

    setUp(() async {
      harness = await _Harness.start();
      auth = <String, String>{
        'authorization': 'Bearer ${harness.issuer.issue(userId: 'user-1')}',
      };
      projectId = await harness.createProject('user-1');
      await harness.pushScene(projectId, 'user-1');
    });

    tearDown(() async {
      await harness.stop();
    });

    test('le partage rend son jeton une seule fois', () async {
      final http.Response created = await harness.post(
        '/v1/projects/$projectId/shares',
        body: <String, Object?>{},
        headers: auth,
      );

      expect(created.statusCode, 201);
      final Map<String, dynamic> data = _dataOf(created);
      final String token = data['token']! as String;
      expect(token.startsWith('ls.'), isTrue);
      expect(token.split('.'), hasLength(3));
      expect(data['project_id'], projectId);
      expect(data['is_revoked'], isFalse);
      expect(data['expires_at'], isNotNull);

      // La base ne garde que l'empreinte du jeton.
      final List<Map<String, Object?>> rows = await harness.rowsOf(
        'SELECT * FROM project_shares',
      );
      expect(rows, hasLength(1));
      expect(rows.first['token_hash'], hasLength(64));
      expect(rows.first.values.join(' '), isNot(contains(token)));

      // La liste ne rend jamais le jeton, ni son empreinte.
      final http.Response listed = await harness.get(
        '/v1/shares',
        headers: auth,
      );
      expect(listed.statusCode, 200);
      expect(listed.body, isNot(contains(token)));
      final Map<String, dynamic> item =
          _itemsOf(listed).first! as Map<String, dynamic>;
      expect(item.containsKey('token'), isFalse);
      expect(item.containsKey('token_hash'), isFalse);
      expect(item['id'], data['id']);
    });

    test('le jeton ouvre le document sans compte', () async {
      final String token = await _createShare(harness, projectId, auth);

      final http.Response response = await harness.get(
        '/v1/shares/$token/document',
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(response);
      expect((data['project']! as Map<String, dynamic>)['id'], projectId);

      final List<dynamic> documents = data['documents']! as List<dynamic>;
      expect(documents, hasLength(1));
      final Map<String, dynamic> document =
          documents.first! as Map<String, dynamic>;
      expect(document['doc_id'], 'doc-1');
      expect(document['blocks'], isNotEmpty);
      expect(
        _blocksOf(
          document,
        ).map((Map<String, dynamic> block) => block['content']),
        contains('Il pleuvait sur la falaise.'),
      );
    });

    test('l\'alias public ouvre le même document', () async {
      final String token = await _createShare(harness, projectId, auth);

      final http.Response response = await harness.get(
        '/v1/public/shares/$token/document',
      );

      expect(response.statusCode, 200);
      expect(
        (_dataOf(response)['project']! as Map<String, dynamic>)['id'],
        projectId,
      );
    });

    test('la page partagée ne dit rien du compte', () async {
      final String otherProject = await harness.createProject('user-1');
      await harness.pushScene(
        otherProject,
        'user-1',
        content: 'Un autre livre.',
      );
      final String token = await _createShare(harness, projectId, auth);

      final http.Response response = await harness.get(
        '/v1/shares/$token/document',
      );

      expect(response.statusCode, 200);
      expect(response.body, isNot(contains('user-1')));
      expect(response.body, isNot(contains(otherProject)));
      expect(response.body, isNot(contains('Un autre livre.')));
      expect(response.body, isNot(contains('owner_id')));
      expect(response.body, isNot(contains('author_id')));
    });

    test('un partage révoqué répond 404', () async {
      final String token = await _createShare(harness, projectId, auth);
      final String shareId = await harness.firstShareId();

      final http.Response revoked = await harness.delete(
        '/v1/shares/$shareId',
        headers: auth,
      );
      expect(revoked.statusCode, 200);
      expect(_dataOf(revoked)['is_revoked'], isTrue);

      final http.Response response = await harness.get(
        '/v1/shares/$token/document',
      );
      expect(response.statusCode, 404);
      expect(_errorOf(response)['code'], 'not_found');
    });

    test('un partage expiré répond 404', () async {
      final String token = await _createShare(harness, projectId, auth);
      await harness.expireShare(await harness.firstShareId());

      final http.Response response = await harness.get(
        '/v1/shares/$token/document',
      );

      expect(response.statusCode, 404);
      expect(_errorOf(response)['code'], 'not_found');
    });

    test('un jeton faux répond 404, jamais 403', () async {
      final http.Response response = await harness.get(
        '/v1/shares/ls.faux-jeton/document',
      );

      expect(response.statusCode, 404);
      expect(_errorOf(response)['code'], 'not_found');
    });

    test(
      'la page partagée ne s\'indexe pas et ne se met pas en cache',
      () async {
        final String token = await _createShare(harness, projectId, auth);

        final http.Response response = await harness.get(
          '/v1/shares/$token/document',
        );

        expect(response.headers['x-robots-tag'], 'noindex');
        expect(response.headers['cache-control'], 'no-store');
      },
    );

    test('le jeton de partage ne pousse aucune opération', () async {
      final String token = await _createShare(harness, projectId, auth);

      final http.Response response = await harness.post(
        '/v1/projects/$projectId/ops',
        body: <String, Object?>{
          'operations': <dynamic>[_operation('user-1')],
        },
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 401);
      expect(harness.sync.storedOperations(projectId), hasLength(1));
    });

    test('un partage ne porte pas le projet d\'un autre compte', () async {
      final String other = await harness.createProject('user-2');

      final http.Response response = await harness.post(
        '/v1/projects/$other/shares',
        body: <String, Object?>{},
        headers: auth,
      );

      expect(response.statusCode, 404);
      expect(_errorOf(response)['code'], 'not_found');
      expect(await harness.rowsOf('SELECT * FROM project_shares'), isEmpty);
    });

    test('seul le propriétaire du livre peut le partager', () async {
      harness.projects.addMember(
        projectId: projectId,
        userId: 'user-3',
        role: ProjectRole.coAuthor,
      );

      final http.Response response = await harness.post(
        '/v1/projects/$projectId/shares',
        body: <String, Object?>{},
        headers: <String, String>{
          'authorization': 'Bearer ${harness.issuer.issue(userId: 'user-3')}',
        },
      );

      expect(response.statusCode, 403);
      expect(_errorOf(response)['code'], 'forbidden');
    });

    test('une route de partage demande un compte', () async {
      final http.Response response = await harness.post(
        '/v1/projects/$projectId/shares',
        body: <String, Object?>{},
      );

      expect(response.statusCode, 401);
    });

    test('la liste ne montre pas les partages d\'un autre compte', () async {
      await _createShare(harness, projectId, auth);

      final http.Response response = await harness.get(
        '/v1/shares',
        headers: <String, String>{
          'authorization': 'Bearer ${harness.issuer.issue(userId: 'user-2')}',
        },
      );

      expect(response.statusCode, 200);
      expect(_itemsOf(response), isEmpty);
    });

    test('share.created et share.revoked sont tracés, sans le jeton', () async {
      final String token = await _createShare(harness, projectId, auth);
      await harness.delete(
        '/v1/shares/${await harness.firstShareId()}',
        headers: auth,
      );

      final List<AuditEntry> entries = harness.audit.entries;
      final AuditEntry created = entries.firstWhere(
        (AuditEntry entry) => entry.action == 'share.created',
      );
      final AuditEntry revoked = entries.firstWhere(
        (AuditEntry entry) => entry.action == 'share.revoked',
      );

      expect(created.userId, 'user-1');
      expect(created.targetType, 'share');
      expect(created.metadata['project_id'], projectId);
      expect(created.metadata['expires_at'], isNotNull);
      expect(revoked.userId, 'user-1');
      expect(revoked.targetId, created.targetId);

      // Le jeton est un secret : il ne se journalise pas.
      final String encoded = jsonEncode(
        entries.map((AuditEntry entry) => entry.toJson()).toList(),
      );
      expect(encoded, isNot(contains(token)));
      expect(encoded, isNot(contains('ls.')));
    });

    test('la route de lecture est limitée en débit', () async {
      final _Harness limited = await _Harness.start(readRateLimitCapacity: 2);
      addTearDown(limited.stop);
      final String project = await limited.createProject('user-1');
      final String token = await _createShare(
        limited,
        project,
        <String, String>{
          'authorization': 'Bearer ${limited.issuer.issue(userId: 'user-1')}',
        },
      );

      expect((await limited.get('/v1/shares/$token/document')).statusCode, 200);
      expect((await limited.get('/v1/shares/$token/document')).statusCode, 200);

      final http.Response refused = await limited.get(
        '/v1/shares/$token/document',
      );
      expect(refused.statusCode, 429);
      expect(_errorOf(refused)['code'], 'rate_limited');
    });
  });
}

/// Crée un partage et rend son jeton.
Future<String> _createShare(
  _Harness harness,
  String projectId,
  Map<String, String> auth,
) async {
  final http.Response response = await harness.post(
    '/v1/projects/$projectId/shares',
    body: <String, Object?>{},
    headers: auth,
  );
  expect(response.statusCode, 201);
  return _dataOf(response)['token']! as String;
}

/// Les blocs d'un document, à plat.
List<Map<String, dynamic>> _blocksOf(Map<String, dynamic> document) {
  final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
  void collect(List<dynamic> current) {
    for (final dynamic block in current) {
      final Map<String, dynamic> map = block as Map<String, dynamic>;
      blocks.add(map);
      collect(map['children']! as List<dynamic>);
    }
  }

  collect(document['blocks']! as List<dynamic>);
  return blocks;
}

/// Une opération de synchronisation.
Map<String, Object?> _operation(String authorId, {int lamport = 2}) {
  return <String, Object?>{
    'op_id': 'op-$lamport',
    'doc_id': 'doc-1',
    'lamport': lamport,
    'author_id': authorId,
    'type': 'insertBlock',
    'payload': <String, Object?>{
      'block_id': 'block-$lamport',
      'parent_id': null,
      'order_key': '5',
      'type': 'paragraph',
      'content': 'Une ligne écrite par le lecteur.',
    },
    'schema_version': 1,
  };
}

/// Les données d'une réponse réussie.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as Map<String, dynamic>;
}

/// Les éléments d'une réponse paginée.
List<dynamic> _itemsOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as List<dynamic>;
}

/// L'erreur d'une réponse en échec.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error']! as Map<String, dynamic>;
}

/// L'API de la suite de tests, avec ses dépendances.
final class _Harness {
  _Harness({
    required this.server,
    required this.database,
    required this.issuer,
    required this.audit,
    required this.projects,
    required this.sync,
  });

  final HttpServer server;
  final SqliteDatabase database;
  final TestTokenIssuer issuer;
  final InMemoryAuditLog audit;
  final InMemoryProjectStore projects;
  final InMemorySyncStore sync;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Démarre l'API de test.
  static Future<_Harness> start({int readRateLimitCapacity = 30}) async {
    final SqliteDatabase database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();

    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
    final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });

    final InMemoryAuditLog audit = InMemoryAuditLog();
    final InMemoryProjectStore projects = InMemoryProjectStore();
    final InMemorySyncStore sync = InMemorySyncStore();
    final AppDependencies dependencies = AppDependencies(
      projects: projects,
      sync: sync,
      audit: audit,
      comments: InMemoryCommentStore(),
      purge: InMemoryAccountPurgeStore(entries: audit.entries),
      ai: StubAiGateway(),
      payments: StubPaymentGateway(),
      storage: InMemoryObjectStorage(),
      keyValue: InMemoryKeyValueStore(),
      jwtVerifier: JwtVerifier(
        jwks: jwks,
        expectedIssuer: 'https://project.test/auth/v1',
      ),
      logger: Logger(level: LogLevel.warning),
      databaseProbe: const AlwaysHealthyProbe(),
      syncHub: SyncHub(),
      shutdown: () async {},
    );

    final AppConfig config = testConfig();
    final Router router = Router();
    registerShareRoutes(
      router,
      dependencies,
      config,
      shares: SqliteShareStore(database),
      readRateLimitCapacity: readRateLimitCapacity,
    );
    // La synchronisation est enregistrée à côté : elle prouve qu'un jeton
    // de partage n'ouvre aucun droit d'écriture.
    registerSyncRoutes(router, dependencies, config);

    final Handler publicHandler = router.call;

    final Handler authenticatedHandler = const Pipeline()
        .addMiddleware(
          authenticationMiddleware(
            verifier: dependencies.jwtVerifier,
            exemptPrefixes: <String>[...publicPathPrefixes, '/v1/api/'],
          ),
        )
        .addHandler(publicHandler);

    // La lecture d'un partage est publique : elle ne demande ni compte ni
    // jeton de session. Le serveur fait la même chose en exemptant ce
    // chemin du middleware d'authentification.
    FutureOr<Response> dispatch(Request request) {
      if (isShareDocumentPath(request.requestedUri.path)) {
        return publicHandler(request);
      }
      return authenticatedHandler(request);
    }

    // Le gestionnaire d'erreurs entoure l'authentification, comme dans le
    // serveur : un refus d'authentification est une réponse, pas une
    // exception qui sort de la pile.
    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning),
            timeout: config.requestTimeout,
          ),
        )
        .addHandler(dispatch);

    final HttpServer server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      0,
    );
    return _Harness(
      server: server,
      database: database,
      issuer: issuer,
      audit: audit,
      projects: projects,
      sync: sync,
    );
  }

  /// Crée un livre possédé par [ownerId].
  Future<String> createProject(String ownerId) async {
    final ProjectRecord project = await projects.create(
      ownerId: ownerId,
      title: 'Le livre',
      synopsis: 'Un synopsis.',
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    return project.id;
  }

  /// Écrit une scène dans le livre [projectId].
  Future<void> pushScene(
    String projectId,
    String authorId, {
    String content = 'Il pleuvait sur la falaise.',
  }) async {
    final http.Response response = await post(
      '/v1/projects/$projectId/ops',
      body: <String, Object?>{
        'operations': <dynamic>[
          <String, Object?>{
            'op_id': 'op-1',
            'doc_id': 'doc-1',
            'lamport': 1,
            'author_id': authorId,
            'type': 'insertBlock',
            'payload': <String, Object?>{
              'block_id': 'block-1',
              'parent_id': null,
              'order_key': '5',
              'type': 'paragraph',
              'content': content,
            },
            'schema_version': 1,
          },
        ],
      },
      headers: <String, String>{
        'authorization': 'Bearer ${issuer.issue(userId: authorId)}',
      },
    );
    expect(response.statusCode, 200);
  }

  /// Les lignes brutes d'une table, pour vérifier ce que la base garde.
  Future<List<Map<String, Object?>>> rowsOf(String sql) async {
    return database.run(() {
      final ResultSet result = database.connection.select(sql);
      return result
          .map(
            (Row row) => <String, Object?>{
              for (final String column in row.keys) column: row[column],
            },
          )
          .toList(growable: false);
    });
  }

  /// Fait expirer le partage [shareId].
  Future<void> expireShare(String shareId) async {
    await database.run(() {
      database.connection.execute(
        'UPDATE project_shares SET expires_at = ? WHERE id = ?',
        <Object?>[0, shareId],
      );
    });
  }

  /// L'identifiant du premier partage de la base.
  Future<String> firstShareId() async {
    final List<Map<String, Object?>> rows = await rowsOf(
      'SELECT * FROM project_shares ORDER BY created_at ASC, id ASC',
    );
    expect(rows, isNotEmpty);
    return rows.first['id']! as String;
  }

  /// Un GET authentifié ou non.
  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.get(Uri.parse('$baseUrl$path'), headers: headers);
  }

  /// Un POST authentifié ou non.
  Future<http.Response> post(
    String path, {
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Un DELETE authentifié ou non.
  Future<http.Response> delete(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.delete(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
    );
  }

  /// Arrête l'API de test.
  Future<void> stop() async {
    await server.close(force: true);
    await database.close();
  }
}
