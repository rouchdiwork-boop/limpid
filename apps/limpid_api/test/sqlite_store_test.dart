import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/audit_log_contract.dart';
import 'helpers/project_store_contract.dart';
import 'helpers/store_fixture.dart';
import 'helpers/sync_store_contract.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  for (final MapEntry<String, Future<StoreFixture> Function()> entry
      in <String, Future<StoreFixture> Function()>{
        'mémoire': _inMemoryFixture,
        'SQLite': _sqliteFixture,
      }.entries) {
    runProjectStoreContract(name: entry.key, build: entry.value);
    runSyncStoreContract(name: entry.key, build: entry.value);
    runAuditLogContract(name: entry.key, build: entry.value);
  }

  group('API sur SQLite', () {
    late HttpServer server;
    late TestTokenIssuer issuer;
    late SqliteDatabase database;
    late String baseUrl;

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

      final AppDependencies dependencies = AppDependencies(
        projects: SqliteProjectStore(database),
        sync: SqliteSyncStore(database),
        audit: SqliteAuditLog(database),
        comments: SqlCommentStore(SqliteCommentDatabase(database)),
        purge: SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database)),
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

      server = await createServer(testConfig(), dependencies: dependencies);
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('répond 401 sans jeton', () async {
      final http.Response response = await http.get(
        Uri.parse('$baseUrl/v1/projects'),
      );

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'unauthorized');
      expect(error['message'], isA<String>());
      expect(error['details'], isA<Map<String, dynamic>>());
    });

    test('crée, lit et supprime un projet', () async {
      final Map<String, String> auth = <String, String>{
        'authorization': 'Bearer ${issuer.issue(userId: 'user-1')}',
      };

      final http.Response created = await http.post(
        Uri.parse('$baseUrl/v1/projects'),
        headers: <String, String>{...auth, 'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{'title': 'Le Vent de Nord'}),
      );
      expect(created.statusCode, 201);
      final Map<String, dynamic> createdBody =
          jsonDecode(created.body) as Map<String, dynamic>;
      final Map<String, dynamic> data =
          createdBody['data'] as Map<String, dynamic>;
      final String id = data['id'] as String;
      expect(data['title'], 'Le Vent de Nord');
      expect(data['status'], 'draft');
      expect(data['language'], 'fr-FR');

      final http.Response listed = await http.get(
        Uri.parse('$baseUrl/v1/projects'),
        headers: auth,
      );
      expect(listed.statusCode, 200);
      final Map<String, dynamic> listedBody =
          jsonDecode(listed.body) as Map<String, dynamic>;
      expect(listedBody['data'], hasLength(1));

      final http.Response deleted = await http.delete(
        Uri.parse('$baseUrl/v1/projects/$id'),
        headers: auth,
      );
      expect(deleted.statusCode, 200);

      final http.Response afterDelete = await http.get(
        Uri.parse('$baseUrl/v1/projects/$id'),
        headers: auth,
      );
      expect(afterDelete.statusCode, 404);
    });

    test('pousse et relit des opérations', () async {
      final Map<String, String> auth = <String, String>{
        'authorization': 'Bearer ${issuer.issue(userId: 'user-1')}',
      };

      final http.Response created = await http.post(
        Uri.parse('$baseUrl/v1/projects'),
        headers: <String, String>{...auth, 'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{'title': 'Manuscrit'}),
      );
      final Map<String, dynamic> createdBody =
          jsonDecode(created.body) as Map<String, dynamic>;
      final String id =
          (createdBody['data'] as Map<String, dynamic>)['id'] as String;

      final Map<String, Object?> operation = <String, Object?>{
        'op_id': 'op-1',
        'doc_id': 'doc-1',
        'lamport': 1,
        'author_id': 'user-1',
        'type': 'insertBlock',
        'schema_version': 1,
        'payload': <String, Object?>{
          'block_id': 'block-1',
          'parent_id': null,
          'order_key': '5',
          'type': 'paragraph',
          'content': 'Il pleuvait sur la falaise.',
        },
      };

      final http.Response pushed = await http.post(
        Uri.parse('$baseUrl/v1/projects/$id/ops'),
        headers: <String, String>{...auth, 'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'operations': <dynamic>[operation],
        }),
      );
      expect(pushed.statusCode, 200);
      final Map<String, dynamic> pushedBody =
          jsonDecode(pushed.body) as Map<String, dynamic>;
      final Map<String, dynamic> pushedData =
          pushedBody['data'] as Map<String, dynamic>;
      expect(pushedData['accepted'], hasLength(1));
      expect(pushedData['lamport_ack'], 1);

      final http.Response pulled = await http.get(
        Uri.parse('$baseUrl/v1/projects/$id/ops?since=0'),
        headers: auth,
      );
      expect(pulled.statusCode, 200);
      expect(jsonDecode(pulled.body)['data'], hasLength(1));
    });
  });
}

/// Builds the fixture of the in-memory stores.
Future<StoreFixture> _inMemoryFixture() async {
  final InMemoryProjectStore projects = InMemoryProjectStore();
  final InMemorySyncStore sync = InMemorySyncStore();
  final InMemoryAuditLog audit = InMemoryAuditLog();

  return StoreFixture(
    projects: projects,
    sync: sync,
    audit: audit,
    addMember:
        ({
          required String projectId,
          required String userId,
          required ProjectRole role,
        }) async {
          projects.addMember(projectId: projectId, userId: userId, role: role);
        },
    dispose: () async {},
  );
}

/// Builds the fixture of the SQLite stores, on an in-memory database.
Future<StoreFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();

  return StoreFixture(
    projects: SqliteProjectStore(database),
    sync: SqliteSyncStore(database),
    audit: SqliteAuditLog(database),
    addMember:
        ({
          required String projectId,
          required String userId,
          required ProjectRole role,
        }) async {
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
        },
    dispose: database.close,
  );
}
