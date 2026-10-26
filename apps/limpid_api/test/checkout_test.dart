import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
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

  Map<String, Object?> body(String plan) => <String, Object?>{
    'plan': plan,
    'success_url': 'https://app.test/merci',
    'cancel_url': 'https://app.test/abandon',
  };

  group('checkout', () {
    test('ouvre une session de paiement', () async {
      final http.Response response = await server.post(
        '/v1/checkout',
        headers: auth,
        body: body('studio'),
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> payload =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = payload['data'] as Map<String, dynamic>;
      expect(data['session_id'], isA<String>());
      expect(data['url'], isA<String>());
    });

    test('journalise le changement de plan', () async {
      await server.post('/v1/checkout', headers: auth, body: body('pro'));

      expect(
        server.audit.entries.any(
          (AuditEntry entry) => entry.action == 'plan.checkout_started',
        ),
        isTrue,
      );
    });

    test('répond 400 et nomme le champ manquant', () async {
      final http.Response response = await server.post(
        '/v1/checkout',
        headers: auth,
        body: <String, Object?>{'plan': 'studio'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> payload =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (payload['error'] as Map<String, dynamic>)['message'],
        contains('success_url'),
      );
    });

    test('rejoue la réponse avec la même clé d\'idempotence', () async {
      final Map<String, String> headers = <String, String>{
        ...auth,
        'idempotency-key': 'cle-1',
      };

      final http.Response first = await server.post(
        '/v1/checkout',
        headers: headers,
        body: body('studio'),
      );
      final http.Response second = await server.post(
        '/v1/checkout',
        headers: headers,
        body: body('studio'),
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(second.body, first.body);
      expect(server.payments.requests, hasLength(1));
    });

    test('refuse la même clé avec un autre corps', () async {
      final Map<String, String> headers = <String, String>{
        ...auth,
        'idempotency-key': 'cle-2',
      };

      await server.post('/v1/checkout', headers: headers, body: body('studio'));
      final http.Response conflict = await server.post(
        '/v1/checkout',
        headers: headers,
        body: body('pro'),
      );

      expect(conflict.statusCode, 409);
      final Map<String, dynamic> payload =
          jsonDecode(conflict.body) as Map<String, dynamic>;
      expect(
        (payload['error'] as Map<String, dynamic>)['code'],
        'idempotency_key_conflict',
      );
    });

    test('relit une session de paiement', () async {
      final http.Response created = await server.post(
        '/v1/checkout',
        headers: auth,
        body: body('studio'),
      );
      final Map<String, dynamic> payload =
          jsonDecode(created.body) as Map<String, dynamic>;
      final String sessionId =
          (payload['data'] as Map<String, dynamic>)['session_id'] as String;

      final http.Response response = await server.get(
        '/v1/checkout/$sessionId',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data =
          (jsonDecode(response.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data['session_id'], sessionId);
      expect(data['url'], isA<String>());
    });

    test('répond 404 sur une session inconnue', () async {
      final http.Response response = await server.get(
        '/v1/checkout/inconnue',
        headers: auth,
      );

      expect(response.statusCode, 404);
    });

    test('répond 404 sur la session d\'un autre compte', () async {
      final http.Response created = await server.post(
        '/v1/checkout',
        headers: auth,
        body: body('studio'),
      );
      final Map<String, dynamic> payload =
          jsonDecode(created.body) as Map<String, dynamic>;
      final String sessionId =
          (payload['data'] as Map<String, dynamic>)['session_id'] as String;

      final http.Response response = await server.get(
        '/v1/checkout/$sessionId',
        headers: <String, String>{
          'authorization': 'Bearer ${server.tokenFor('user-2')}',
        },
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> error =
          (jsonDecode(response.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      expect(error['code'], 'not_found');
      expect(response.body, isNot(contains('checkout.test')));
    });

    test('isole les clés d\'idempotence par compte', () async {
      final Map<String, String> headers = <String, String>{
        ...auth,
        'idempotency-key': 'cle-partagee',
      };
      final Map<String, String> otherHeaders = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-2')}',
        'idempotency-key': 'cle-partagee',
      };

      final http.Response first = await server.post(
        '/v1/checkout',
        headers: headers,
        body: body('studio'),
      );
      final http.Response other = await server.post(
        '/v1/checkout',
        headers: otherHeaders,
        body: body('studio'),
      );

      expect(first.statusCode, 200);
      expect(other.statusCode, 200);

      final String firstSession =
          ((jsonDecode(first.body) as Map<String, dynamic>)['data']
                  as Map<String, dynamic>)['session_id']
              as String;
      final String otherSession =
          ((jsonDecode(other.body) as Map<String, dynamic>)['data']
                  as Map<String, dynamic>)['session_id']
              as String;

      // L'autre compte ne reçoit pas la session du premier.
      expect(otherSession, isNot(firstSession));

      // Le premier compte rejoue sa propre réponse.
      final http.Response replay = await server.post(
        '/v1/checkout',
        headers: headers,
        body: body('studio'),
      );
      expect(replay.statusCode, 200);
      expect(replay.body, first.body);
      expect(server.payments.requests, hasLength(2));
    });

    test('refuse un corps plus gros que la limite', () async {
      final TestServer small = await startTestServer(
        configOverrides: <String, String>{'MAX_BODY_BYTES': '1024'},
      );
      addTearDown(small.stop);

      final http.Response response = await small.post(
        '/v1/checkout',
        headers: <String, String>{
          'authorization': 'Bearer ${small.tokenFor('user-1')}',
        },
        body: <String, Object?>{
          'plan': 'studio',
          'success_url': 'https://app.test/merci',
          'cancel_url': 'https://app.test/abandon',
          'padding': 'x' * 4096,
        },
      );

      expect(response.statusCode, 413);
      final Map<String, dynamic> error =
          (jsonDecode(response.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      expect(error['code'], 'payload_too_large');
    });

    test('limite l\'ouverture des sessions de paiement', () async {
      var limited = false;
      for (var attempt = 0; attempt < 12 && !limited; attempt++) {
        final http.Response response = await server.post(
          '/v1/checkout',
          headers: auth,
          body: body('studio'),
        );
        if (response.statusCode == 429) {
          limited = true;
          final Map<String, dynamic> error =
              (jsonDecode(response.body) as Map<String, dynamic>)['error']
                  as Map<String, dynamic>;
          expect(error['code'], 'rate_limited');
        }
      }

      expect(limited, isTrue);
    });
  });
}
