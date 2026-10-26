import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

/// A client HTTP that answers a checkout session and keeps the body it was
/// given.
final class _RecordingClient extends http.BaseClient {
  String? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Request typed = request as http.Request;
    body = typed.body;
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'id': 'cs_test_1',
            'url': 'https://checkout.stripe.test/c/pay/cs_test_1',
          }),
        ),
      ),
      200,
    );
  }
}

void main() {
  group('prix des formules', () {
    test('viennent du domaine partagé, pas d une seconde liste', () {
      expect(planPriceInCents('free'), PlanDefinition.free.priceInCents);
      expect(planPriceInCents('writer'), PlanDefinition.writer.priceInCents);
      expect(planPriceInCents('pro'), PlanDefinition.pro.priceInCents);
      expect(planPriceInCents('studio'), PlanDefinition.studio.priceInCents);
      expect(
        planPriceInCents('studio_yearly'),
        PlanDefinition.studioYearly.priceInCents,
      );
    });

    test('respectent D-15', () {
      expect(planPriceInCents('writer'), 999);
      expect(planPriceInCents('pro'), 2499);
      expect(planPriceInCents('studio'), 4999);
      expect(planPriceInCents('studio_yearly'), 49900);
    });

    test('refusent une formule inconnue au lieu de facturer une autre', () {
      expect(
        () => planPriceInCents('enterprise'),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException error) => error.field,
            'field',
            'plan',
          ),
        ),
      );
    });

    test('la casse du nom de la formule n a pas d importance', () {
      expect(planPriceInCents('PRO'), planPriceInCents('pro'));
    });
  });

  group('session Stripe', () {
    late _RecordingClient client;

    setUp(() {
      client = _RecordingClient();
    });

    test('facture le prix de la formule demandée', () async {
      final StripePaymentGateway gateway = StripePaymentGateway(
        secretKey: 'sk_test',
        client: client,
      );

      await gateway.createSession(
        const CheckoutRequest(
          userId: 'user-1',
          plan: 'pro',
          successUrl: 'https://app.test/merci',
          cancelUrl: 'https://app.test/abandon',
        ),
      );

      expect(
        Uri.splitQueryString(client.body ?? '')[
            'line_items[0][price_data][unit_amount]'],
        '2499',
      );
    });

    test('refuse une formule inconnue', () async {
      final StripePaymentGateway gateway = StripePaymentGateway(
        secretKey: 'sk_test',
        client: client,
      );

      await expectLater(
        gateway.createSession(
          const CheckoutRequest(
            userId: 'user-1',
            plan: 'inexistante',
            successUrl: 'https://app.test/merci',
            cancelUrl: 'https://app.test/abandon',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(client.body, isNull);
    });
  });
}
