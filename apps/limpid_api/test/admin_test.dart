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
  group('back-office sur SQLite', () {
    late SqliteDatabase database;
    late SqliteAdminDatabase admin;
    late SqliteAuditLog audit;
    late _AdminServer server;
    late String adminToken;
    late String userToken;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();
      admin = SqliteAdminDatabase(database);
      audit = SqliteAuditLog(database);
      server = await _startAdminServer(admin);
      adminToken = _tokenWithRole(server, userId: 'admin-1', role: 'admin');
      userToken = _tokenWithRole(
        server,
        userId: 'user-1',
        role: 'authenticated',
      );
      await _seedAccounts(database);
    });

    tearDown(() async {
      await server.stop();
      await database.close();
    });

    group('accès réservé', () {
      test('refuse un appelant ordinaire sur la liste des comptes', () async {
        final http.Response response = await server.get(
          '/v1/admin/users',
          token: userToken,
        );

        expect(response.statusCode, 403);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        expect((body['error'] as Map<String, dynamic>)['code'], 'forbidden');
      });

      test('refuse un appelant ordinaire sur le détail d\'un compte', () async {
        final http.Response response = await server.get(
          '/v1/admin/users/user-1',
          token: userToken,
        );

        expect(response.statusCode, 403);
      });

      test('refuse un appelant ordinaire sur les indicateurs', () async {
        final http.Response response = await server.get(
          '/v1/admin/feature-flags',
          token: userToken,
        );

        expect(response.statusCode, 403);
      });

      test(
        'refuse un appelant ordinaire sur un changement d\'indicateur',
        () async {
          final http.Response response = await server.put(
            '/v1/admin/feature-flags/ai_premium',
            body: <String, Object?>{'enabled': true},
            token: userToken,
          );

          expect(response.statusCode, 403);
        },
      );

      test('refuse un appelant sans jeton', () async {
        final http.Response response = await server.get('/v1/admin/users');

        expect(response.statusCode, 401);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        expect((body['error'] as Map<String, dynamic>)['code'], 'unauthorized');
      });
    });

    group('comptes', () {
      test(
        'liste les comptes dédupliqués avec leur formule et leur usage',
        () async {
          final http.Response response = await server.get(
            '/v1/admin/users',
            token: adminToken,
          );

          expect(response.statusCode, 200);
          final Map<String, dynamic> body =
              jsonDecode(response.body) as Map<String, dynamic>;
          final List<dynamic> data = body['data'] as List<dynamic>;
          final Map<String, Map<String, dynamic>> accounts = _accountsById(
            data,
          );

          expect(accounts, hasLength(3));
          expect((body['meta'] as Map<String, dynamic>)['total'], 3);

          expect(accounts['user-1']!['plan'], 'ecrivain');
          expect(accounts['user-1']!['project_count'], 1);
          expect(accounts['user-1']!['collaboration_count'], 0);
          expect(accounts['user-1']!['is_purged'], isFalse);

          expect(accounts['user-2']!['plan'], isNull);
          expect(accounts['user-2']!['project_count'], 0);
          expect(accounts['user-2']!['collaboration_count'], 1);

          expect(accounts['user-3']!['comment_count'], 1);
          expect(accounts['user-3']!['operation_count'], 1);
        },
      );

      test('lit le détail d\'un compte', () async {
        final http.Response response = await server.get(
          '/v1/admin/users/user-3',
          token: adminToken,
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        final Map<String, dynamic> account =
            body['data'] as Map<String, dynamic>;
        expect(account['user_id'], 'user-3');
        expect(account['comment_count'], 1);
        expect(account['operation_count'], 1);
      });

      test('ne rend aucun compte pour un identifiant inconnu', () async {
        final http.Response response = await server.get(
          '/v1/admin/users/inconnu',
          token: adminToken,
        );

        expect(response.statusCode, 404);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        expect((body['error'] as Map<String, dynamic>)['code'], 'not_found');
      });

      test('renvoie une page et un curseur cohérents', () async {
        final http.Response first = await server.get(
          '/v1/admin/users?limit=2',
          token: adminToken,
        );

        expect(first.statusCode, 200);
        final Map<String, dynamic> body =
            jsonDecode(first.body) as Map<String, dynamic>;
        final List<dynamic> data = body['data'] as List<dynamic>;
        final Map<String, dynamic> meta = body['meta'] as Map<String, dynamic>;

        expect(data, hasLength(2));
        expect(meta['total'], 3);
        expect(meta['limit'], 2);
        expect(meta['next_cursor'], isA<String>());

        final http.Response second = await server.get(
          '/v1/admin/users?limit=2&cursor=${meta['next_cursor']}',
          token: adminToken,
        );

        expect(second.statusCode, 200);
        final Map<String, dynamic> secondBody =
            jsonDecode(second.body) as Map<String, dynamic>;
        final List<dynamic> remaining = secondBody['data'] as List<dynamic>;

        expect(remaining, hasLength(1));
        expect((remaining.first as Map<String, dynamic>)['user_id'], 'user-1');
        expect(
          (secondBody['meta'] as Map<String, dynamic>)['next_cursor'],
          isNull,
        );
      });

      test('refuse une page qui dépasse la limite', () async {
        final http.Response response = await server.get(
          '/v1/admin/users?limit=100000',
          token: adminToken,
        );

        expect(response.statusCode, 400);
      });
    });

    group('indicateurs de fonctionnalité', () {
      test('active puis désactive un indicateur et relit son état', () async {
        final http.Response enabled = await server.put(
          '/v1/admin/feature-flags/ai_premium',
          body: <String, Object?>{
            'enabled': true,
            'description': 'Les fonctions IA de la formule Pro.',
          },
          token: adminToken,
        );

        expect(enabled.statusCode, 200);
        final Map<String, dynamic> data =
            (jsonDecode(enabled.body) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        expect(data['key'], 'ai_premium');
        expect(data['is_enabled'], isTrue);
        expect(data['description'], 'Les fonctions IA de la formule Pro.');
        expect(data['updated_by'], 'admin-1');

        final http.Response listed = await server.get(
          '/v1/admin/feature-flags',
          token: adminToken,
        );
        expect(listed.statusCode, 200);
        final List<dynamic> flags =
            (jsonDecode(listed.body) as Map<String, dynamic>)['data']
                as List<dynamic>;
        expect(flags, hasLength(1));
        expect((flags.first as Map<String, dynamic>)['is_enabled'], isTrue);

        final http.Response disabled = await server.put(
          '/v1/admin/feature-flags/ai_premium',
          body: <String, Object?>{'enabled': false},
          token: adminToken,
        );
        expect(disabled.statusCode, 200);
        final Map<String, dynamic> after =
            (jsonDecode(disabled.body) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        expect(after['is_enabled'], isFalse);
        expect(after['description'], 'Les fonctions IA de la formule Pro.');
      });

      test('écrit une entrée d\'audit à chaque changement', () async {
        await server.put(
          '/v1/admin/feature-flags/ai_premium',
          body: <String, Object?>{'enabled': true},
          token: adminToken,
        );
        await server.put(
          '/v1/admin/feature-flags/ai_premium',
          body: <String, Object?>{'enabled': false},
          token: adminToken,
        );

        final List<AuditEntry> entries = await audit.entriesOf(
          userId: 'admin-1',
          limit: 10,
        );

        expect(entries, hasLength(2));
        expect(
          entries.every(
            (AuditEntry entry) =>
                entry.action == 'admin.feature_flag_changed' &&
                entry.targetId == 'ai_premium',
          ),
          isTrue,
        );
      });

      test('refuse une clé d\'indicateur mal formée', () async {
        final http.Response response = await server.put(
          '/v1/admin/feature-flags/Cl%C3%A9!',
          body: <String, Object?>{'enabled': true},
          token: adminToken,
        );

        expect(response.statusCode, 400);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        expect(
          (body['error'] as Map<String, dynamic>)['code'],
          'validation_failed',
        );
      });

      test(
        'refuse un corps qui ne dit pas si l\'indicateur est actif',
        () async {
          final http.Response response = await server.put(
            '/v1/admin/feature-flags/ai_premium',
            body: <String, Object?>{},
            token: adminToken,
          );

          expect(response.statusCode, 400);
        },
      );
    });
  });

  group('back-office en mémoire', () {
    late InMemoryAdminDatabase admin;
    late _AdminServer server;
    late String adminToken;

    setUp(() async {
      admin = InMemoryAdminDatabase();
      admin.addAccount(
        userId: 'user-1',
        projectCount: 2,
        lastActivityAt: DateTime.utc(2026, 10, 20),
      );
      admin.addAccount(
        userId: 'user-2',
        collaborationCount: 1,
        lastActivityAt: DateTime.utc(2026, 10, 21),
      );
      admin.assignPlan(userId: 'user-2', plan: 'pro');
      server = await _startAdminServer(admin);
      adminToken = _tokenWithRole(server, userId: 'admin-1', role: 'admin');
    });

    tearDown(() async {
      await server.stop();
    });

    test('liste les comptes avec leur formule', () async {
      final http.Response response = await server.get(
        '/v1/admin/users',
        token: adminToken,
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> data = body['data'] as List<dynamic>;
      final Map<String, Map<String, dynamic>> accounts = _accountsById(data);

      expect(accounts, hasLength(2));
      expect(accounts['user-2']!['plan'], 'pro');
      expect(accounts['user-2']!['project_count'], 0);
      expect(accounts['user-2']!['collaboration_count'], 1);
      expect(accounts['user-1']!['plan'], isNull);
      expect(accounts['user-1']!['project_count'], 2);
    });

    test('écrit les changements d\'indicateur dans le journal', () async {
      await server.put(
        '/v1/admin/feature-flags/ai_premium',
        body: <String, Object?>{'enabled': true},
        token: adminToken,
      );

      final List<AuditEntry> entries = await admin.audit.entriesOf(
        userId: 'admin-1',
        limit: 10,
      );

      expect(entries, hasLength(1));
      expect(entries.first.action, 'admin.feature_flag_changed');
      expect(entries.first.targetId, 'ai_premium');
    });
  });
}

/// The accounts of a page, by identifier.
Map<String, Map<String, dynamic>> _accountsById(List<dynamic> data) {
  final Map<String, Map<String, dynamic>> accounts =
      <String, Map<String, dynamic>>{};
  for (final dynamic item in data) {
    final Map<String, dynamic> account = item as Map<String, dynamic>;
    accounts[account['user_id']! as String] = account;
  }
  return accounts;
}

/// A server exposing the back-office, for the tests.
final class _AdminServer {
  _AdminServer({
    required this.server,
    required this.issuer,
    required this.keyPair,
  });

  /// The running server.
  final HttpServer server;

  /// The issuer of the test tokens.
  final TestTokenIssuer issuer;

  /// The key pair signing the test tokens.
  final TestRsaKeyPair keyPair;

  /// The base URL of the server.
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Performs a GET request.
  Future<http.Response> get(String path, {String? token}) {
    return http.get(Uri.parse('$baseUrl$path'), headers: _headers(token));
  }

  /// Performs a PUT request.
  Future<http.Response> put(String path, {Object? body, String? token}) {
    return http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token, withBody: true),
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Stops the server.
  Future<void> stop() => server.close(force: true);

  /// The headers of a request, the token is optional.
  Map<String, String> _headers(String? token, {bool withBody = false}) {
    return <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
      if (withBody) 'content-type': 'application/json',
    };
  }
}

/// Starts the back-office on an ephemeral port.
Future<_AdminServer> _startAdminServer(AdminDatabase database) async {
  final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
  final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
  final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
    issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
  });
  final JwtVerifier verifier = JwtVerifier(
    jwks: jwks,
    expectedIssuer: 'https://project.test/auth/v1',
  );

  final List<String> logLines = <String>[];
  final Logger logger = Logger(level: LogLevel.warning, sink: logLines.add);

  final AppConfig config = testConfig();
  final Router router = Router();
  registerAdminRoutes(router, database, config);

  final Handler handler = const Pipeline()
      .addMiddleware(
        errorHandlerMiddleware(logger: logger, timeout: config.requestTimeout),
      )
      .addMiddleware(authenticationMiddleware(verifier: verifier))
      .addHandler(router.call);

  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    0,
  );
  return _AdminServer(server: server, issuer: issuer, keyPair: keyPair);
}

/// Issues a token carrying [role] for [userId].
///
/// The tokens of the test suite carry the role of a signed in account; the
/// back-office needs a token signed with the role of an administrator.
String _tokenWithRole(
  _AdminServer server, {
  required String userId,
  required String role,
}) {
  final String token = server.issuer.issue(userId: userId);
  final List<String> parts = token.split('.');
  final Map<String, dynamic> payload =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
  final String encoded = base64Url.encode(
    utf8.encode(jsonEncode(<String, dynamic>{...payload, 'role': role})),
  );
  final String signingInput = '${parts[0]}.$encoded';
  final String signature = base64Url.encode(
    server.keyPair.sign(utf8.encode(signingInput)),
  );
  return '$signingInput.$signature';
}

/// Fills the database with the accounts the back-office lists.
///
/// The accounts are the owner of a project, a collaborator and the author
/// of a message and of an operation: the API only knows the identifiers it
/// met in its own tables.
Future<void> _seedAccounts(SqliteDatabase database) async {
  final SqliteProjectStore projects = SqliteProjectStore(database);
  final ProjectRecord project = await projects.create(
    ownerId: 'user-1',
    title: 'Les Heures de Cendre',
    synopsis: 'Une archiviste et une cloche.',
    status: ManuscriptStatus.draft,
    language: 'fr-FR',
    orderKey: '5',
  );

  final DateTime now = DateTime.now().toUtc();
  final int recent = SqliteValues.encodeTimestamp(now);
  final int earlier = SqliteValues.encodeTimestamp(
    now.subtract(const Duration(minutes: 1)),
  );
  final int oldest = SqliteValues.encodeTimestamp(
    now.subtract(const Duration(minutes: 3)),
  );

  await database.run(() {
    database.connection.execute(
      'UPDATE projects SET updated_at = ? WHERE id = ?',
      <Object?>[oldest, project.id],
    );
    database.connection.execute(
      'INSERT INTO project_members '
      '(project_id, user_id, role, created_at) VALUES (?, ?, ?, ?)',
      <Object?>[project.id, 'user-2', ProjectRole.coAuthor.name, recent],
    );
    database.connection.execute(
      'INSERT INTO comment_threads '
      '(id, project_id, mark_id, excerpt, is_resolved, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'thread-1',
        project.id,
        'mark-1',
        'Il pleuvait sur la falaise.',
        0,
        earlier,
        earlier,
      ],
    );
    database.connection.execute(
      'INSERT INTO comments '
      '(id, thread_id, author_id, body, created_at) VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        'comment-1',
        'thread-1',
        'user-3',
        'La falaise rend bien la scène.',
        earlier,
      ],
    );
    database.connection.execute(
      'INSERT INTO sync_ops '
      '(id, project_id, doc_id, lamport, author_id, type, payload, '
      'schema_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'op-1',
        project.id,
        'doc-1',
        1,
        'user-3',
        'insertBlock',
        '{}',
        1,
        oldest,
      ],
    );

    // La table des formules appartient au module qui possede les plans : le
    // test en pose une pour verifier que le back-office la lit.
    database.connection.execute('DROP TABLE IF EXISTS subscriptions');
    database.connection.execute(
      'CREATE TABLE subscriptions ('
      ' id TEXT PRIMARY KEY,'
      ' user_id TEXT NOT NULL,'
      ' plan TEXT NOT NULL,'
      " status TEXT NOT NULL DEFAULT 'active')",
    );
    database.connection.execute(
      'INSERT INTO subscriptions (id, user_id, plan, status) '
      'VALUES (?, ?, ?, ?)',
      <Object?>['sub-1', 'user-1', 'ecrivain', 'active'],
    );
  });
}
