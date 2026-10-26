import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_plan_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_core/limpid_core.dart';

void main() {
  group('ApiPlanRepository', () {
    test('lit la formule du compte', () async {
      final ApiPlanRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/plan');
        return _ok(<String, Object?>{
          'plan': 'writer',
          'name': 'Écrivain',
          'status': 'trial',
          'period': 'monthly',
          'trial_ends_at': '2026-11-08T00:00:00.000Z',
          'period_started_at': '2026-10-25T00:00:00.000Z',
          'period_ends_at': '2026-11-24T00:00:00.000Z',
          'seat_count': 1,
        });
      });

      final AccountPlan plan = await repository.currentPlan();

      expect(plan.plan, SubscriptionPlan.writer);
      expect(plan.displayName, 'Écrivain');
      expect(plan.status, PlanStatus.trial);
      expect(plan.period, BillingPeriod.monthly);
      expect(plan.trialEndsAt, DateTime.utc(2026, 11, 8));
      expect(plan.periodEndsAt, DateTime.utc(2026, 11, 24));
    });

    test('lit le catalogue et ses limites', () async {
      final ApiPlanRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/plans');
        return _ok(<Object?>[
          <String, Object?>{
            'plan': 'studio',
            'name': 'Studio',
            'price_cents': 4999,
            'yearly_price_cents': 49900,
            'trial_days': 0,
            'seat_count': 5,
            'quota': <String, Object?>{
              'words': 10000000,
              'ai_rewrites': 1000,
              'storage_bytes': 10737418240,
            },
            'capabilities': <String>['rag'],
          },
        ]);
      });

      final List<PlanOffer> offers = await repository.offers();

      expect(offers, hasLength(1));
      final PlanOffer studio = offers.first;
      expect(studio.plan, SubscriptionPlan.studio);
      expect(studio.priceInCents, 4999);
      expect(studio.yearlyPriceInCents, 49900);
      expect(studio.seatCount, 5);
      expect(studio.maxWords, 10000000);
      expect(studio.maxAiUsage, 1000);
      expect(studio.maxStorageBytes, 10737418240);
      expect(studio.offers(BillingPeriod.yearly), isTrue);
    });

    test('lit les compteurs du cycle', () async {
      final ApiPlanRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/quota');
        return _ok(<String, Object?>{
          'plan': 'pro',
          'period': 'monthly',
          'quotas': <Object?>[
            <String, Object?>{
              'feature': 'words',
              'kind': 'gauge',
              'limit': 10000000,
              'used': null,
            },
            <String, Object?>{
              'feature': 'ai_rewrites',
              'kind': 'counter',
              'limit': 1000,
              'used': 341,
            },
            <String, Object?>{
              'feature': 'storage_bytes',
              'kind': 'gauge',
              'limit': 1073741824,
              'used': null,
            },
            <String, Object?>{
              'feature': 'ai_tokens',
              'kind': 'counter',
              'limit': 2000000,
              'used': 341200,
            },
            <String, Object?>{
              'feature': 'ai_covers',
              'kind': 'counter',
              'limit': 5,
              'used': 2,
            },
          ],
        });
      });

      final List<QuotaReading> readings = await repository.usage();

      expect(readings, hasLength(5));
      expect(readings.first.meter, QuotaMeter.words);
      expect(readings.first.limit, 10000000);
      expect(readings.first.used, isNull);
      expect(readings[1].meter, QuotaMeter.aiUsage);
      expect(readings[1].used, 341);
      expect(readings[1].ratio, closeTo(0.341, 0.0001));
      expect(readings[2].meter, QuotaMeter.storage);
      // Les jetons de l'IA se comptent a part des reecritures : le
      // produit se vend en jetons, l'auteur veut voir ce qu'il consomme.
      expect(readings[3].meter, QuotaMeter.aiTokens);
      expect(readings[3].limit, 2000000);
      expect(readings[3].used, 341200);
      // Les couvertures se comptent a part : la formule en accorde cinq
      // par mois, et l'auteur doit voir ce qu'il en a produit.
      expect(readings[4].meter, QuotaMeter.aiCovers);
      expect(readings[4].limit, 5);
      expect(readings[4].used, 2);
    });

    test('ouvre une session de paiement', () async {
      Map<String, Object?>? body;
      final ApiPlanRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/checkout');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'session_id': 'cs_1',
          'url': 'https://checkout.test/cs_1',
          'status': 'open',
        });
      }, origin: Uri.parse('https://app.test'));

      final CheckoutSession session = await repository.openCheckout(
        plan: SubscriptionPlan.studio,
        period: BillingPeriod.yearly,
        returnTo: Uri.parse('/abonnement'),
      );

      expect(body?['plan'], 'studio_yearly');
      expect(body?['success_url'], 'https://app.test/abonnement');
      expect(body?['cancel_url'], 'https://app.test/abonnement');
      expect(session.id, 'cs_1');
      expect(session.url, 'https://checkout.test/cs_1');
    });

    test(
      'refuse le paiement quand l’application ne connaît pas son adresse',
      () async {
        final ApiPlanRepository repository = _repositoryOf(
          (http.Request request) async => _ok(<String, Object?>{}),
        );

        await expectLater(
          repository.openCheckout(
            plan: SubscriptionPlan.pro,
            period: BillingPeriod.monthly,
            returnTo: Uri.parse('/abonnement'),
          ),
          throwsA(isA<ServiceUnavailableException>()),
        );
      },
    );

    test(
      'porte une clé d idempotence : deux clics, une seule session',
      () async {
        // Un double-clic sur « Payer » ne doit pas ouvrir deux sessions de
        // paiement : la cle d'idempotence fait rejouer la premiere reponse.
        final List<String?> keys = <String?>[];
        DateTime now = DateTime.utc(2026, 10, 26, 9);
        final ApiPlanRepository repository = _repositoryOf(
          (http.Request request) async {
            keys.add(request.headers['idempotency-key']);
            return _ok(<String, Object?>{
              'session_id': 'cs_1',
              'url': 'https://checkout.test/cs_1',
              'status': 'open',
            });
          },
          origin: Uri.parse('https://app.test'),
          clock: () => now,
        );

        Future<CheckoutSession> open() => repository.openCheckout(
          plan: SubscriptionPlan.studio,
          period: BillingPeriod.yearly,
          returnTo: Uri.parse('/abonnement'),
        );

        await open();
        now = now.add(const Duration(minutes: 2));
        await open();

        expect(keys.first, isNotNull);
        expect(keys.first, isNotEmpty);
        expect(keys[1], keys.first);

        // Une commande reprise plus tard ouvre une session neuve : l'ancienne
        // a pu expirer.
        now = now.add(const Duration(minutes: 20));
        await open();

        expect(keys[2], isNot(keys.first));
      },
    );

    test('remonte une erreur typée quand le serveur refuse', () async {
      final ApiPlanRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'unauthorized',
              'message': 'Session expirée.',
            },
          }),
          401,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.currentPlan(),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiPlanRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler, {
  Uri? origin,
  DateTime Function()? clock,
}) => ApiPlanRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
  checkoutOrigin: origin,
  clock: clock,
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);
