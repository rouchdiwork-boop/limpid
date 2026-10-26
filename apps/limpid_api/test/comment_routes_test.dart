import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  late SqliteDatabase database;
  late HttpServer server;
  late TestTokenIssuer issuer;
  late SqliteProjectStore projects;
  late String baseUrl;
  late String projectId;

  setUp(() async {
    database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();

    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
    issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });

    projects = SqliteProjectStore(database);
    final AppDependencies dependencies = AppDependencies(
      projects: projects,
      sync: SqliteSyncStore(database),
      audit: SqliteAuditLog(database),
      comments: SqlCommentStore(SqliteCommentDatabase(database)),
      purge: InMemoryAccountPurgeStore(entries: const <AuditEntry>[]),
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
      shutdown: database.close,
    );

    final AppConfig config = testConfig();
    final Router router = Router();
    registerCommentRoutes(
      router,
      dependencies,
      config,
      comments: SqlCommentStore(SqliteCommentDatabase(database)),
    );

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: dependencies.logger,
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(
          authenticationMiddleware(verifier: dependencies.jwtVerifier),
        )
        .addHandler(router.call);

    server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';

    final ProjectRecord project = await projects.create(
      ownerId: 'user-1',
      title: 'Les Heures de Cendre',
      synopsis: 'Une archiviste et une cloche.',
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    projectId = project.id;
  });

  tearDown(() async {
    await server.close(force: true);
    await database.close();
  });

  Future<void> addMember(String userId, ProjectRole role) async {
    await database.run(() {
      database.connection.execute(
        'INSERT INTO project_members '
        '(project_id, user_id, role, created_at) VALUES (?, ?, ?, ?)',
        <Object?>[
          projectId,
          userId,
          role.name,
          SqliteValues.encodeTimestamp(DateTime.now().toUtc()),
        ],
      );
    });
  }

  Future<http.Response> read(String path, {String userId = 'user-1'}) async {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'authorization': 'Bearer ${issuer.issue(userId: userId)}',
      },
    );
  }

  Future<http.Response> write(
    String path,
    Map<String, Object?> payload, {
    String userId = 'user-1',
  }) async {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'authorization': 'Bearer ${issuer.issue(userId: userId)}',
        'content-type': 'application/json',
      },
      body: jsonEncode(payload),
    );
  }

  group('discussions', () {
    test('écrit une discussion et la relit', () async {
      final http.Response created = await write(
        '/v1/projects/$projectId/threads',
        _threadOf(),
      );

      expect(created.statusCode, 201);
      final Map<String, dynamic> body =
          jsonDecode(created.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['id'], 'thread-1');
      expect(data['mark_id'], 'mark-1');
      expect(data['excerpt'], 'Il pleuvait sur la falaise.');
      expect(data['is_resolved'], isFalse);
      expect(data['comments'], hasLength(1));

      final http.Response listed = await read(
        '/v1/projects/$projectId/threads',
      );

      expect(listed.statusCode, 200);
      final Map<String, dynamic> listedBody =
          jsonDecode(listed.body) as Map<String, dynamic>;
      final List<dynamic> threads = listedBody['data'] as List<dynamic>;
      expect(threads, hasLength(1));
      final Map<String, dynamic> thread = threads.first as Map<String, dynamic>;
      expect(thread['id'], 'thread-1');
      final List<dynamic> comments = thread['comments'] as List<dynamic>;
      expect(comments, hasLength(1));
      expect(
        (comments.first as Map<String, dynamic>)['body'],
        'La falaise rend bien la scène.',
      );
    });

    test('met à jour une discussion déjà écrite', () async {
      await write('/v1/projects/$projectId/threads', _threadOf());

      final http.Response updated =
          await write('/v1/projects/$projectId/threads', <String, Object?>{
            ..._threadOf(),
            'is_resolved': true,
            'resolved_at': '2026-10-25T10:00:00.000Z',
          });

      expect(updated.statusCode, 201);
      final Map<String, dynamic> body =
          jsonDecode(updated.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['is_resolved'], isTrue);
      expect(data['resolved_at'], '2026-10-25T10:00:00.000Z');
    });

    test('ne rend aucune discussion pour un projet inconnu', () async {
      final http.Response response = await read(
        '/v1/projects/projet-inconnu/threads',
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'not_found');
    });
  });

  group('autorisation', () {
    test('refuse un appelant qui ne collabore pas au projet', () async {
      final http.Response response = await read(
        '/v1/projects/$projectId/threads',
        userId: 'user-2',
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'not_found');
      expect(error['message'], isA<String>());
      expect(error['details'], isA<Map<String, dynamic>>());
    });

    test('refuse l\'écriture d\'un appelant qui ne collabore pas', () async {
      final http.Response response = await write(
        '/v1/projects/$projectId/threads',
        _threadOf(),
        userId: 'user-2',
      );

      expect(response.statusCode, 404);
    });

    test('refuse un appelant sans jeton', () async {
      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/projects/$projectId/threads'),
      );

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'unauthorized');
    });

    test('refuse à un lecteur d\'écrire une discussion', () async {
      await addMember('user-3', ProjectRole.reader);

      final http.Response response = await write(
        '/v1/projects/$projectId/threads',
        _threadOf(),
        userId: 'user-3',
      );

      expect(response.statusCode, 403);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'forbidden');
    });
  });

  group('collaborateurs', () {
    test('liste le propriétaire et les collaborateurs', () async {
      await addMember('user-2', ProjectRole.betaReader);

      final http.Response response = await read(
        '/v1/projects/$projectId/members',
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> members = body['data'] as List<dynamic>;
      expect(members, hasLength(2));
      final Map<String, dynamic> owner = members.first as Map<String, dynamic>;
      expect(owner['user_id'], 'user-1');
      expect(owner['role'], 'owner');
      final Map<String, dynamic> reader = members.last as Map<String, dynamic>;
      expect(reader['user_id'], 'user-2');
      expect(reader['role'], 'betaReader');
    });

    test('refuse un appelant qui ne collabore pas', () async {
      final http.Response response = await read(
        '/v1/projects/$projectId/members',
        userId: 'user-2',
      );

      expect(response.statusCode, 404);
    });
  });
}

/// The body of a discussion.
Map<String, Object?> _threadOf() {
  return <String, Object?>{
    'id': 'thread-1',
    'mark_id': 'mark-1',
    'excerpt': 'Il pleuvait sur la falaise.',
    'is_resolved': false,
    'comments': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'comment-1',
        'author_id': 'user-1',
        'body': 'La falaise rend bien la scène.',
        'created_at': '2026-10-25T09:12:33.412Z',
      },
    ],
  };
}
