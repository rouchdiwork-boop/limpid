import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> auth;

  setUp(() async {
    server = await startTestServer();
    // La formule gratuite n'autorise que deux appels au modele par jour :
    // les tests de la limitation de debit ont besoin d'une formule qui
    // laisse passer les appels, pour que ce soit le seau qui morde.
    await server.givePlan('user-1', SubscriptionPlan.writer);
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
  });

  tearDown(() async {
    await server.stop();
  });

  /// Donne au compte [userId] la formule [plan].
  ///
  /// La recherche dans le manuscrit n'est ouverte qu'aux formules qui la
  /// comprennent (D-15) : le test qui l'exerce doit donc donner une formule
  /// à son compte.
  Future<void> givePlan(String userId, SubscriptionPlan plan) async {
    final InMemoryQuotaDatabase quotas =
        server.dependencies.quotas! as InMemoryQuotaDatabase;
    await quotas.assignPlan(
      AccountPlan(
        userId: userId,
        plan: plan,
        period: BillingPeriod.monthly,
        periodStartedAt: DateTime.now().toUtc(),
      ),
    );
  }

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
      await givePlan('user-1', SubscriptionPlan.pro);
      // La formule Pro exige la double authentification (D-19).
      final String proof = await server.enableTwoFactor('user-1');

      final http.Response response = await server.post(
        '/v1/ai/query',
        headers: <String, String>{...auth, 'x-limpid-2fa': proof},
        body: <String, Object?>{'question': 'Qui est le capitaine ?'},
      );

      expect(response.statusCode, 200);
      expect(response.body, contains('event: done'));
    });

    test('refuse la recherche hors formule qui l’ouvre', () async {
      final http.Response response = await server.post(
        '/v1/ai/query',
        headers: auth,
        body: <String, Object?>{'question': 'Qui est le capitaine ?'},
      );

      expect(response.statusCode, 402);
      expect(response.body, contains('plan_limit_reached'));
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
