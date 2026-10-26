import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

/// Les gardes-fous du lot 7 : une formule ne s'attribue pas, un essai ne se
/// recommence pas, et les limites de la formule s'appliquent vraiment.
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

  Map<String, Object?> planBody(String plan, {bool startTrial = false}) =>
      <String, Object?>{'plan': plan, if (startTrial) 'start_trial': true};

  group('attribution d une formule', () {
    test('un compte ne s attribue pas une formule payée', () async {
      final http.Response response = await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('studio'),
      );

      expect(response.statusCode, 403);
      expect(response.body, contains('forbidden'));
    });

    test(
      'un compte ne s attribue pas la formule Écrivain sans essai',
      () async {
        final http.Response response = await server.post(
          '/v1/me/plan',
          headers: auth,
          body: planBody('writer'),
        );

        expect(response.statusCode, 403);
      },
    );

    test('un compte peut revenir a la formule gratuite', () async {
      final http.Response response = await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('free'),
      );

      expect(response.statusCode, 200);
    });

    test(
      'l administrateur attribue une formule payée après un paiement',
      () async {
        final http.Response response = await server.put(
          '/v1/admin/plans/user-1',
          headers: <String, String>{
            'authorization':
                'Bearer ${server.issuer.issue(userId: 'admin', role: 'admin')}',
          },
          body: <String, Object?>{
            'plan': 'pro',
            'payment_reference': 'pi_1234',
          },
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> payload =
            jsonDecode(response.body) as Map<String, dynamic>;
        final Map<String, dynamic> data =
            payload['data'] as Map<String, dynamic>;
        expect(data['plan'], 'pro');
      },
    );

    test('un compte ordinaire n attribue pas de formule a un autre', () async {
      final http.Response response = await server.put(
        '/v1/admin/plans/user-2',
        headers: auth,
        body: <String, Object?>{'plan': 'pro', 'payment_reference': 'pi_1234'},
      );

      expect(response.statusCode, 403);
    });
  });

  group('essai gratuit', () {
    test('se demande une fois', () async {
      final http.Response first = await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('writer', startTrial: true),
      );
      expect(first.statusCode, 200);

      final http.Response second = await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('writer', startTrial: true),
      );
      expect(second.statusCode, 409);
      expect(second.body, contains('conflict'));
    });

    test('ne se rearme pas apres un retour a la formule gratuite', () async {
      await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('writer', startTrial: true),
      );
      await server.post('/v1/me/plan', headers: auth, body: planBody('free'));

      final http.Response again = await server.post(
        '/v1/me/plan',
        headers: auth,
        body: planBody('writer', startTrial: true),
      );
      expect(again.statusCode, 409);
    });
  });

  group('jauges de la formule', () {
    test('la formule gratuite refuse un second projet', () async {
      final http.Response first = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'title': 'Premier livre'},
      );
      expect(first.statusCode, 201);

      final http.Response second = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'title': 'Second livre'},
      );
      expect(second.statusCode, 402);
      expect(second.body, contains('plan_limit_reached'));
    });

    test('la formule Écrivain accepte dix projets', () async {
      final InMemoryQuotaDatabase quotas =
          server.dependencies.quotas! as InMemoryQuotaDatabase;
      await quotas.assignPlan(
        AccountPlan(
          userId: 'user-1',
          plan: SubscriptionPlan.writer,
          period: BillingPeriod.monthly,
          periodStartedAt: DateTime.now().toUtc(),
        ),
      );

      for (int index = 0; index < 10; index++) {
        final http.Response response = await server.post(
          '/v1/projects',
          headers: auth,
          body: <String, Object?>{'title': 'Livre $index'},
        );
        expect(response.statusCode, 201, reason: 'projet $index');
      }

      final http.Response refused = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'title': 'Livre de trop'},
      );
      expect(refused.statusCode, 402);
    });
  });
}
