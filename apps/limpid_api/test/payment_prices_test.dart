import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

/// Un appel reçu par Stripe.
final class _StripeCall {
  /// Crée un appel.
  const _StripeCall({required this.body, required this.headers});

  /// Le corps de la requête, lu comme un formulaire.
  final Map<String, String> body;

  /// Les en-têtes de la requête.
  final Map<String, String> headers;
}

/// Un service de paiement simulé : il répond une session et garde les
/// appels qu'il a reçus.
final class _FakeStripe {
  /// Les appels reçus, dans l'ordre.
  final List<_StripeCall> calls = <_StripeCall>[];

  /// Le client qui répond une session de paiement.
  late final MockClient client = MockClient(_answer);

  /// Le corps du dernier appel, vide quand il n'y en a pas eu.
  Map<String, String> get body =>
      calls.isEmpty ? const <String, String>{} : calls.last.body;

  /// Les en-têtes du dernier appel, vides quand il n'y en a pas eu.
  Map<String, String> get headers =>
      calls.isEmpty ? const <String, String>{} : calls.last.headers;

  Future<http.Response> _answer(http.Request request) async {
    calls.add(
      _StripeCall(
        body: Uri.splitQueryString(request.body),
        headers: request.headers,
      ),
    );
    return http.Response(
      jsonEncode(<String, Object?>{
        'id': 'cs_test_1',
        'url': 'https://checkout.stripe.test/c/pay/cs_test_1',
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

/// La commande d'un abonnement, prête à être envoyée.
CheckoutRequest _order({
  SubscriptionPlan plan = SubscriptionPlan.pro,
  BillingPeriod period = BillingPeriod.monthly,
  String? idempotencyKey,
  bool startTrial = false,
}) {
  return CheckoutRequest(
    userId: 'user-1',
    plan: plan,
    period: period,
    successUrl: 'https://app.test/merci',
    cancelUrl: 'https://app.test/abandon',
    idempotencyKey: idempotencyKey,
    startTrial: startTrial,
  );
}

void main() {
  group('résolution de la commande', () {
    test('porte le cycle demandé', () {
      final SubscriptionOrder order = SubscriptionOrder.resolve(
        planKey: 'studio',
        period: BillingPeriod.yearly,
      );

      expect(order.plan, SubscriptionPlan.studio);
      expect(order.period, BillingPeriod.yearly);
      expect(order.key, 'studio_yearly');
    });

    test('déduit le cycle annuel du nom de la formule', () {
      final SubscriptionOrder order = SubscriptionOrder.resolve(
        planKey: 'studio_yearly',
      );

      expect(order.plan, SubscriptionPlan.studio);
      expect(order.period, BillingPeriod.yearly);
    });

    test('refuse un cycle que la formule ne propose pas', () {
      expect(
        () => SubscriptionOrder.resolve(
          planKey: 'writer',
          period: BillingPeriod.yearly,
        ),
        throwsA(
          isA<ValidationException>()
              .having(
                (ValidationException error) => error.field,
                'field',
                'period',
              )
              .having(
                (ValidationException error) => error.message,
                'message',
                contains('period'),
              ),
        ),
      );
    });

    test('refuse une formule qui n\'existe pas', () {
      expect(
        () => SubscriptionOrder.resolve(planKey: 'enterprise'),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'plan',
          ),
        ),
      );
    });

    test('refuse la formule gratuite', () {
      expect(
        () => SubscriptionOrder.resolve(planKey: 'free'),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'plan',
          ),
        ),
      );
    });

    test('refuse un nom de formule qui contredit le cycle demandé', () {
      expect(
        () => SubscriptionOrder.resolve(
          planKey: 'studio_yearly',
          period: BillingPeriod.monthly,
        ),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'period',
          ),
        ),
      );
    });
  });

  group('prix des formules', () {
    test('viennent du domaine partagé, pas d une seconde liste', () {
      expect(
        SubscriptionOrder(
          plan: SubscriptionPlan.writer,
          period: BillingPeriod.monthly,
        ).priceInCents,
        PlanDefinition.writer.priceInCents,
      );
      expect(
        SubscriptionOrder(
          plan: SubscriptionPlan.pro,
          period: BillingPeriod.monthly,
        ).priceInCents,
        PlanDefinition.pro.priceInCents,
      );
      expect(
        SubscriptionOrder(
          plan: SubscriptionPlan.studio,
          period: BillingPeriod.monthly,
        ).priceInCents,
        PlanDefinition.studio.priceInCents,
      );
      expect(
        SubscriptionOrder(
          plan: SubscriptionPlan.studio,
          period: BillingPeriod.yearly,
        ).priceInCents,
        PlanDefinition.studioYearly.priceInCents,
      );
    });

    test('respectent D-15', () {
      expect(PlanDefinition.writer.priceInCents, 999);
      expect(PlanDefinition.pro.priceInCents, 2499);
      expect(PlanDefinition.studio.priceInCents, 4999);
      expect(PlanDefinition.studioYearly.priceInCents, 49900);
    });
  });

  group('session Stripe', () {
    late _FakeStripe stripe;
    late StripePaymentGateway gateway;

    setUp(() {
      stripe = _FakeStripe();
      gateway = StripePaymentGateway(
        secretKey: 'sk_test',
        client: stripe.client,
      );
    });

    test('ouvre un abonnement, pas un paiement unique', () async {
      await gateway.createSession(_order());

      expect(stripe.body['mode'], 'subscription');
      expect(
        stripe.body['line_items[0][price_data][recurring][interval]'],
        'month',
      );
      expect(
        stripe.body['line_items[0][price_data][recurring][interval_count]'],
        '1',
      );
    });

    test('porte le compte et la formule sur l\'abonnement', () async {
      await gateway.createSession(_order(plan: SubscriptionPlan.pro));

      // Stripe ne recopie pas les métadonnées de la session sur
      // l'abonnement : le webhook de paiement les lit sur l'abonnement.
      expect(stripe.body['subscription_data[metadata][user_id]'], 'user-1');
      expect(stripe.body['subscription_data[metadata][plan]'], 'pro');
      expect(stripe.body['metadata[user_id]'], 'user-1');
      expect(stripe.body['metadata[plan]'], 'pro');
      expect(stripe.body['client_reference_id'], 'user-1');
    });

    test('le cycle annuel porte l\'intervalle year', () async {
      await gateway.createSession(
        _order(plan: SubscriptionPlan.studio, period: BillingPeriod.yearly),
      );

      expect(
        stripe.body['line_items[0][price_data][recurring][interval]'],
        'year',
      );
      expect(stripe.body['subscription_data[metadata][plan]'], 'studio_yearly');
    });

    test('l\'essai de 14 jours ne concerne que la formule Écrivain', () async {
      await gateway.createSession(
        _order(plan: SubscriptionPlan.writer, startTrial: true),
      );
      expect(stripe.body['subscription_data[trial_period_days]'], '14');

      await gateway.createSession(
        _order(plan: SubscriptionPlan.pro, startTrial: true),
      );
      expect(
        stripe.body.containsKey('subscription_data[trial_period_days]'),
        isFalse,
      );

      await gateway.createSession(
        _order(plan: SubscriptionPlan.studio, startTrial: true),
      );
      expect(
        stripe.body.containsKey('subscription_data[trial_period_days]'),
        isFalse,
      );
    });

    test(
      'un compte qui a deja consomme son essai n en recoit pas un second',
      () async {
        // La decision appartient a la route, qui lit l'historique du compte :
        // le port ne l'accorde que si on le lui demande.
        await gateway.createSession(_order(plan: SubscriptionPlan.writer));
        expect(
          stripe.body.containsKey('subscription_data[trial_period_days]'),
          isFalse,
        );
      },
    );

    test('transmet la clé d\'idempotence à Stripe', () async {
      await gateway.createSession(_order(idempotencyKey: 'cle-1'));

      final String? key = stripe.headers['idempotency-key'];
      expect(key, isNotNull);
      expect(key, isNotEmpty);
    });

    test('facture le prix du domaine partagé', () async {
      const List<(SubscriptionPlan, BillingPeriod)> orders =
          <(SubscriptionPlan, BillingPeriod)>[
            (SubscriptionPlan.writer, BillingPeriod.monthly),
            (SubscriptionPlan.pro, BillingPeriod.monthly),
            (SubscriptionPlan.studio, BillingPeriod.monthly),
            (SubscriptionPlan.studio, BillingPeriod.yearly),
          ];

      for (final (SubscriptionPlan plan, BillingPeriod period) in orders) {
        final _FakeStripe call = _FakeStripe();
        await StripePaymentGateway(
          secretKey: 'sk_test',
          client: call.client,
        ).createSession(_order(plan: plan, period: period));

        final int expected = period == BillingPeriod.yearly
            ? PlanDefinition.studioYearly.priceInCents
            : PlanDefinition.of(plan).priceInCents;
        expect(
          call.body['line_items[0][price_data][unit_amount]'],
          '$expected',
          reason: 'le montant de ${plan.name} sur le cycle ${period.name}',
        );
      }
    });

    test('refuse la formule gratuite', () async {
      await expectLater(
        gateway.createSession(_order(plan: SubscriptionPlan.free)),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'plan',
          ),
        ),
      );
      expect(stripe.calls, isEmpty);
    });

    test('refuse un cycle que la formule ne propose pas', () async {
      await expectLater(
        gateway.createSession(
          _order(plan: SubscriptionPlan.writer, period: BillingPeriod.yearly),
        ),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'period',
          ),
        ),
      );
      expect(stripe.calls, isEmpty);
    });
  });
}
