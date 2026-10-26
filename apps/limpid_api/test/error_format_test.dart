import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> auth;

  setUp(() async {
    server = await startTestServer();
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
  });

  tearDown(() async {
    await server.stop();
  });

  group('enveloppe d\'erreur', () {
    test('répond 401 avec l\'enveloppe exacte', () async {
      final http.Response response = await server.get('/v1/projects');

      expect(response.statusCode, 401);
      expect(response.headers['content-type'], contains('application/json'));

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(body.keys, <String>['error']);

      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error.keys.toSet(), <String>{'code', 'message', 'details'});
      expect(error['code'], 'unauthorized');
      expect(error['message'], isA<String>());
      expect(error['details'], isA<Map<String, dynamic>>());
    });

    test('répond 404 avec l\'enveloppe exacte', () async {
      final http.Response response = await server.get(
        '/v1/projects/inconnu',
        headers: auth,
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(body.keys, <String>['error']);
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'not_found');
    });

    test('répond 400 avec l\'enveloppe exacte', () async {
      final http.Response response = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'validation_failed');
      expect(error['message'], contains('title'));
    });

    test('ne renvoie jamais de trace d\'exécution', () async {
      final http.Response response = await server.get(
        '/v1/projects/inconnu',
        headers: auth,
      );

      expect(response.body, isNot(contains('#0')));
      expect(response.body, isNot(contains('stack')));
      expect(response.body, isNot(contains('.dart')));
    });
  });

  group('enveloppe de succès', () {
    test('renvoie les données sous la clé "data"', () async {
      final http.Response response = await server.get('/health');

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(body.keys, <String>['data']);
    });

    test('renvoie la pagination sous la clé "meta"', () async {
      final http.Response response = await server.get(
        '/v1/projects?limit=10',
        headers: auth,
      );

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), <String>{'data', 'meta'});

      final Map<String, dynamic> meta = body['meta'] as Map<String, dynamic>;
      expect(meta.keys, <String>['total', 'page', 'limit', 'next_cursor']);
    });
  });
}
