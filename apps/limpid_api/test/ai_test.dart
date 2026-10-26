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

  group('routes IA', () {
    test('stream les jetons et l\'événement done', () async {
      final http.Response response = await server.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/event-stream'));
      expect(response.body, contains('event: token'));
      expect(response.body, contains('event: done'));
      expect(response.body, contains('Texte '));
    });

    test('répond 400 et nomme le champ manquant', () async {
      final http.Response response = await server.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'instruction': 'Sans invite.'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('prompt'),
      );
    });

    test('répond 400 sur une action inline inconnue', () async {
      final http.Response response = await server.post(
        '/v1/ai/inline',
        headers: auth,
        body: <String, Object?>{'action': 'inconnue', 'text': 'Un passage.'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('action'),
      );
    });

    test('interroge le manuscrit', () async {
      final http.Response response = await server.post(
        '/v1/ai/query',
        headers: auth,
        body: <String, Object?>{'question': 'Qui est le capitaine ?'},
      );

      expect(response.statusCode, 200);
      expect(response.body, contains('event: done'));
    });
  });

  group('limitation de débit', () {
    test('répond 429 et "rate_limited" au-delà de la limite', () async {
      for (var i = 0; i < 3; i++) {
        final http.Response allowed = await server.post(
          '/v1/ai/generate',
          headers: auth,
          body: <String, Object?>{'prompt': 'Invite $i'},
        );
        expect(allowed.statusCode, 200);
      }

      final http.Response limited = await server.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Invite refusée'},
      );

      expect(limited.statusCode, 429);
      final Map<String, dynamic> body =
          jsonDecode(limited.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'rate_limited');
      expect(error['message'], isA<String>());
    });

    test('ne limite pas les autres routes', () async {
      for (var i = 0; i < 5; i++) {
        final http.Response response = await server.get(
          '/v1/projects',
          headers: auth,
        );
        expect(response.statusCode, 200);
      }
    });
  });
}
