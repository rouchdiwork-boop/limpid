import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  late TestServer server;

  setUp(() async {
    server = await startTestServer();
  });

  tearDown(() async {
    await server.stop();
  });

  group('authentification', () {
    test('répond 401 et "unauthorized" sans jeton', () async {
      final http.Response response = await server.get('/v1/projects');

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'unauthorized');
      expect(error['message'], isA<String>());
    });

    test('répond 401 et "token_expired" avec un jeton expiré', () async {
      final String token = server.issuer.issue(
        userId: 'user-1',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'token_expired');
    });

    test('répond 200 avec un jeton valide', () async {
      final String token = server.tokenFor('user-1');

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['data'], isA<List<dynamic>>());
      expect(body['meta'], isA<Map<String, dynamic>>());
    });

    test('répond 401 avec un jeton mal formé', () async {
      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer pas-un-jeton'},
      );

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'unauthorized');
    });

    test('rejette un jeton signé par une clé inconnue', () async {
      final TestRsaKeyPair other = generateTestKeyPair(bits: 1024);
      final String token = TestTokenIssuer(other).issue(userId: 'user-1');

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 401);
    });

    test('rejette un jeton dont la signature a été altérée', () async {
      final String token = server.tokenFor('user-1');
      final List<String> parts = token.split('.');
      final String tampered =
          '${parts[0]}.${parts[1]}.${parts[2].substring(0, parts[2].length - 2)}AA';

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $tampered'},
      );

      expect(response.statusCode, 401);
    });

    test('rejette un jeton émis par une autre source', () async {
      final String token = server.issuer.issue(
        userId: 'user-1',
        issuer: 'https://attaquant.test/auth/v1',
      );

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 401);
    });

    test('rejette un jeton qui ne cible pas l\'application', () async {
      final String token = server.issuer.issue(
        userId: 'user-1',
        audience: 'autre-application',
      );

      final http.Response response = await server.get(
        '/v1/projects',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      expect(response.statusCode, 401);
    });
  });

  group('routes publiques', () {
    test('GET /health répond 200 sans jeton', () async {
      final http.Response response = await server.get('/health');

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['data'] as Map<String, dynamic>)['status'], 'ok');
    });

    test('GET /ready répond 200 sans jeton', () async {
      final http.Response response = await server.get('/ready');

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['status'], 'ready');
      expect(data['database'], isTrue);
      expect(data['redis'], isTrue);
    });

    test('la réponse porte un en-tête X-Request-Id', () async {
      final http.Response response = await server.get('/health');

      expect(response.headers['x-request-id'], isNotNull);
    });
  });
}
