import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

/// Le secret du point de rappel Stripe, dans la suite de tests.
const String webhookSecret = 'whsec_secret_de_test';

void main() {
  group('vente des livres', () {
    late _Harness harness;
    late String projectId;

    setUp(() async {
      harness = await _Harness.start();
      projectId = await harness.createProject('auteur-1');
    });

    tearDown(() async {
      await harness.stop();
    });

    group('mise en vente', () {
      test('le proprietaire met son livre en vente', () async {
        final http.Response response = await harness.put(
          '/v1/books/$projectId/sale',
          body: <String, Object?>{'price_cents': 1200, 'currency': 'eur'},
          headers: harness.auth('auteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['price_cents'], 1200);
        expect(data['currency'], 'eur');
        expect(data['status'], 'published');
        expect(data['author_share'], 9000);
        expect(data['platform_share'], 1000);
        expect(data['is_free'], isFalse);
      });

      test('un prix negatif est refuse', () async {
        final http.Response response = await harness.put(
          '/v1/books/$projectId/sale',
          body: <String, Object?>{'price_cents': -1, 'currency': 'eur'},
          headers: harness.auth('auteur-1'),
        );

        expect(response.statusCode, 400);
        expect(harness.errorOf(response)['message'], contains('price_cents'));
      });

      test('une devise hors liste est refusee', () async {
        final http.Response response = await harness.put(
          '/v1/books/$projectId/sale',
          body: <String, Object?>{'price_cents': 1200, 'currency': 'usd'},
          headers: harness.auth('auteur-1'),
        );

        expect(response.statusCode, 400);
        expect(harness.errorOf(response)['message'], contains('currency'));
      });

      test('un compte qui n\'a pas le livre ne le met pas en vente', () async {
        final http.Response response = await harness.put(
          '/v1/books/$projectId/sale',
          body: <String, Object?>{'price_cents': 1200, 'currency': 'eur'},
          headers: harness.auth('auteur-2'),
        );

        expect(response.statusCode, 404);
      });

      test('la part de l\'auteur est configurable', () async {
        final http.Response response = await harness.put(
          '/v1/books/$projectId/sale',
          body: <String, Object?>{
            'price_cents': 1000,
            'currency': 'eur',
            'author_share': 7000,
          },
          headers: harness.auth('auteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['author_share'], 7000);
        expect(data['platform_share'], 3000);
      });

      test('le prix du livre est lisible par l\'acheteur', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final http.Response response = await harness.get(
          '/v1/books/$projectId/sale',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        expect(harness.dataOf(response)['price_cents'], 1200);
      });

      test(
        'un livre en preparation n\'est pas visible par l\'acheteur',
        () async {
          await harness.publish(
            projectId,
            priceInCents: 1200,
            status: BookSaleStatus.draft,
          );

          final http.Response response = await harness.get(
            '/v1/books/$projectId/sale',
            headers: harness.auth('acheteur-1'),
          );

          expect(response.statusCode, 404);
        },
      );

      test('le prix se lit sans compte', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.showInShowcase(projectId);

        final http.Response response = await harness.get(
          '/v1/public/books/$projectId/sale',
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['price_cents'], 1200);
        expect(data['currency'], 'eur');
        expect(data['status'], 'published');
        // La part de l'auteur et le proprietaire restent sur le serveur :
        // un lecteur n'a pas a les connaitre.
        expect(data.containsKey('author_share'), isFalse);
        expect(data.containsKey('owner_id'), isFalse);
      });

      test(
        'un livre en vente mais pas dans la vitrine na pas de prix public',
        () async {
          await harness.publish(projectId, priceInCents: 1200);

          final http.Response response = await harness.get(
            '/v1/public/books/$projectId/sale',
          );

          // Le livre est en vente, mais son auteur ne l'a pas publie : la
          // vitrine ne dit rien de lui.
          expect(response.statusCode, 404);
        },
      );

      test('un livre en preparation n\'a pas de prix public', () async {
        await harness.publish(
          projectId,
          priceInCents: 1200,
          status: BookSaleStatus.draft,
        );

        final http.Response response = await harness.get(
          '/v1/public/books/$projectId/sale',
        );

        expect(response.statusCode, 404);
      });

      test('un livre inconnu n\'a pas de prix public', () async {
        final http.Response response = await harness.get(
          '/v1/public/books/projet-inconnu/sale',
        );

        expect(response.statusCode, 404);
      });
    });

    group('commande', () {
      test('un livre sans prix ne se vend pas', () async {
        final http.Response response = await harness.bookCheckout(
          'projet-inconnu',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 404);
        expect(harness.errorOf(response)['message'], contains('en vente'));
        expect(harness.payments.bookRequests, isEmpty);
      });

      test('un livre en preparation ne se vend pas', () async {
        await harness.publish(
          projectId,
          priceInCents: 1200,
          status: BookSaleStatus.draft,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 409);
        expect(harness.errorOf(response)['message'], contains('publié'));
        expect(harness.payments.bookRequests, isEmpty);
      });

      test('un livre retire de la vente ne se vend pas', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.publish(
          projectId,
          priceInCents: 1200,
          status: BookSaleStatus.withdrawn,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 409);
        expect(harness.errorOf(response)['message'], contains('retiré'));
        expect(harness.payments.bookRequests, isEmpty);
      });

      test('le prix vient de la base, jamais du corps', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'price_cents': 1},
        );

        expect(response.statusCode, 200);
        expect(harness.payments.bookRequests.single.priceInCents, 1200);
        expect(harness.dataOf(response)['amount_cents'], 1200);
      });

      test('la commande ouvre une session de paiement pour le livre', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['session_id'], isA<String>());
        expect(data['url'], isA<String>());
        expect(data['granted'], isFalse);
        final BookCheckoutRequest request =
            harness.payments.bookRequests.single;
        expect(request.projectId, projectId);
        expect(request.userId, 'acheteur-1');
        expect(request.priceInCents, 1200);
        expect(request.currency, 'eur');
      });

      test('la commande est idempotente', () async {
        await harness.publish(projectId, priceInCents: 1200);
        final Map<String, String> headers = <String, String>{
          ...harness.auth('acheteur-1'),
          'idempotency-key': 'cle-1',
        };

        final http.Response first = await harness.bookCheckout(
          projectId,
          headers: headers,
        );
        final http.Response second = await harness.bookCheckout(
          projectId,
          headers: headers,
        );

        expect(first.statusCode, 200);
        expect(second.statusCode, 200);
        expect(second.body, first.body);
        expect(harness.payments.bookRequests, hasLength(1));
      });

      test('un livre gratuit accorde le droit sans ventiler', () async {
        await harness.publish(projectId, priceInCents: 0);

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['is_free'], isTrue);
        expect(data['granted'], isTrue);
        expect(data['amount_cents'], 0);
        // Aucun paiement n'est demande pour un livre gratuit.
        expect(harness.payments.bookRequests, isEmpty);

        final EntitlementRecord? entitlement = await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: projectId,
        );
        expect(entitlement, isNotNull);
        expect(entitlement!.amountInCents, 0);
        expect(entitlement.authorAmountInCents, 0);
        expect(entitlement.platformAmountInCents, 0);
      });

      test('un livre gratuit ne demande pas de session de paiement', () async {
        await harness.publish(projectId, priceInCents: 0);

        await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(harness.payments.bookRequests, isEmpty);
      });
    });

    group('droit de lecture', () {
      test('un paiement confirme accorde un droit de lecture', () async {
        await harness.publish(projectId, priceInCents: 1200);

        await harness.deliverBookPayment(
          eventId: 'evt_1',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        final EntitlementRecord? entitlement = await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: projectId,
        );
        expect(entitlement, isNotNull);
        expect(entitlement!.source, 'cs_test_evt_1');
      });

      test('le rejeu du meme evenement ne cree pas deux droits', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final StripeWebhookResult first = await harness.deliverBookPayment(
          eventId: 'evt_2',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );
        final StripeWebhookResult second = await harness.deliverBookPayment(
          eventId: 'evt_2',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        expect(first.outcome, StripeWebhookOutcome.applied);
        expect(second.outcome, StripeWebhookOutcome.replayed);
        final List<EntitlementRecord> owned = await harness.entitlements
            .listByUser('acheteur-1');
        expect(owned, hasLength(1));
      });

      test('un paiement non encaisse n\'accorde aucun droit', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final StripeWebhookResult result = await harness.deliverBookPayment(
          eventId: 'evt_3',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
          paymentStatus: 'unpaid',
        );

        expect(result.outcome, StripeWebhookOutcome.ignored);
        expect(
          await harness.entitlements.find(
            userId: 'acheteur-1',
            projectId: projectId,
          ),
          isNull,
        );
      });

      test('sans droit, le telechargement repond 404', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final http.Response response = await harness.get(
          '/v1/purchases/$projectId/download',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 404);
        expect(harness.errorOf(response)['code'], 'not_found');
      });

      test('le droit donne une URL signee de vingt-quatre heures', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.deliverBookPayment(
          eventId: 'evt_4',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        final http.Response response = await harness.get(
          '/v1/purchases/$projectId/download',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['download_url'], isA<String>());
        expect(data['expires_in_seconds'], 86400);
        expect(data['expires_at'], isNotNull);
      });

      test('le telechargement d\'un livre que l\'on n\'a pas achete repond '
          '404', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.deliverBookPayment(
          eventId: 'evt_5',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        final http.Response response = await harness.get(
          '/v1/purchases/$projectId/download',
          headers: harness.auth('acheteur-2'),
        );

        expect(response.statusCode, 404);
      });

      test('la liste des achats rend les livres achetés', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.deliverBookPayment(
          eventId: 'evt_6',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        final http.Response response = await harness.get(
          '/v1/purchases',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        final List<dynamic> data = jsonDecode(response.body)['data'] as List;
        expect(data, hasLength(1));
        expect((data.first as Map<String, dynamic>)['project_id'], projectId);
      });

      test('la liste des achats ne montre pas les livres des autres', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.deliverBookPayment(
          eventId: 'evt_7',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1200,
        );

        final http.Response response = await harness.get(
          '/v1/purchases',
          headers: harness.auth('acheteur-2'),
        );

        expect(response.statusCode, 200);
        expect(jsonDecode(response.body)['data'], isEmpty);
      });
    });

    group('ventilation', () {
      test('la ventilation est de 90/10 par defaut', () async {
        await harness.publish(projectId, priceInCents: 1000);
        await harness.deliverBookPayment(
          eventId: 'evt_10',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1000,
        );

        final EntitlementRecord entitlement = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: projectId,
        ))!;

        expect(entitlement.authorShare, 9000);
        expect(entitlement.platformShare, 1000);
        expect(entitlement.authorAmountInCents, 900);
        expect(entitlement.platformAmountInCents, 100);
        expect(
          entitlement.authorAmountInCents + entitlement.platformAmountInCents,
          1000,
        );
      });

      test('la part configuree par le compte est appliquee', () async {
        await harness.publish(projectId, priceInCents: 1000, authorShare: 7000);
        await harness.deliverBookPayment(
          eventId: 'evt_11',
          userId: 'acheteur-1',
          projectId: projectId,
          amountTotal: 1000,
        );

        final EntitlementRecord entitlement = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: projectId,
        ))!;

        expect(entitlement.authorAmountInCents, 700);
        expect(entitlement.platformAmountInCents, 300);
      });

      test('la ventilation n\'est ecrite qu\'au paiement', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
        );

        expect(
          await harness.entitlements.find(
            userId: 'acheteur-1',
            projectId: projectId,
          ),
          isNull,
        );
      });
    });

    group('code promo', () {
      test('un code en pourcentage applique la bonne remise', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'BIENVENUE',
          discountType: PromoDiscountType.percent,
          value: 2500,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'bienvenue'},
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['discount_cents'], 300);
        expect(data['amount_cents'], 900);
        expect(data['promo_code'], 'bienvenue');
        expect(harness.payments.bookRequests.single.priceInCents, 900);
      });

      test('un code de montant fixe applique la bonne remise', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'CINQUIETE',
          discountType: PromoDiscountType.amount,
          value: 200,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'CINQUIETE'},
        );

        expect(response.statusCode, 200);
        expect(harness.dataOf(response)['amount_cents'], 1000);
      });

      test('un code inconnu est refuse', () async {
        await harness.publish(projectId, priceInCents: 1200);

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'INCONNU'},
        );

        expect(response.statusCode, 400);
        expect(harness.errorOf(response)['message'], contains('INCONNU'));
      });

      test('un code expire est refuse et nomme sa raison', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'PERIME',
          discountType: PromoDiscountType.percent,
          value: 2500,
          expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'PERIME'},
        );

        expect(response.statusCode, 409);
        expect(harness.errorOf(response)['message'], contains('expiré'));
        expect(
          (harness.errorOf(response)['details']
              as Map<String, dynamic>)['reason'],
          'expired',
        );
      });

      test('un code epuise est refuse et nomme sa raison', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'UNIQUE',
          discountType: PromoDiscountType.percent,
          value: 2500,
          maxUses: 1,
        );
        await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-2'),
          body: <String, Object?>{'promo_code': 'UNIQUE'},
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-3'),
          body: <String, Object?>{'promo_code': 'UNIQUE'},
        );

        expect(response.statusCode, 409);
        expect(harness.errorOf(response)['message'], contains('quota'));
        expect(
          (harness.errorOf(response)['details']
              as Map<String, dynamic>)['reason'],
          'exhausted',
        );
      });

      test('un code deja utilise par ce compte est refuse', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'BIENVENUE',
          discountType: PromoDiscountType.percent,
          value: 2500,
          maxUses: 10,
        );
        await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'BIENVENUE'},
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'BIENVENUE'},
        );

        expect(response.statusCode, 409);
        expect(harness.errorOf(response)['message'], contains('déjà'));
        expect(
          (harness.errorOf(response)['details']
              as Map<String, dynamic>)['reason'],
          'already_used',
        );
      });

      test('la remise ne rend jamais le prix negatif', () async {
        await harness.publish(projectId, priceInCents: 500);
        await harness.createPromoCode(
          code: 'GEANT',
          discountType: PromoDiscountType.amount,
          value: 100000,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'GEANT'},
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['amount_cents'], 0);
        expect(data['discount_cents'], 500);
      });

      test('une remise de 100 pour cent rend le livre gratuit', () async {
        await harness.publish(projectId, priceInCents: 1200);
        await harness.createPromoCode(
          code: 'TOTAL',
          discountType: PromoDiscountType.percent,
          value: 10000,
        );

        final http.Response response = await harness.bookCheckout(
          projectId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'TOTAL'},
        );

        expect(response.statusCode, 200);
        expect(harness.dataOf(response)['granted'], isTrue);
        expect(harness.payments.bookRequests, isEmpty);
      });

      test('l\'administration cree un code promo', () async {
        final http.Response response = await harness.post(
          '/v1/admin/promo-codes',
          body: <String, Object?>{
            'code': 'NOUVEAU',
            'discount_type': 'percent',
            'value': 1000,
            'max_uses': 50,
            'expires_at': '2027-01-01T00:00:00Z',
          },
          headers: harness.adminAuth(),
        );

        expect(response.statusCode, 201);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['code'], 'nouveau');
        expect(data['value'], 1000);
        expect(data['max_uses'], 50);
      });

      test('un compte ordinaire ne cree pas de code promo', () async {
        final http.Response response = await harness.post(
          '/v1/admin/promo-codes',
          body: <String, Object?>{
            'code': 'NOUVEAU',
            'discount_type': 'percent',
            'value': 1000,
            'max_uses': 50,
            'expires_at': '2027-01-01T00:00:00Z',
          },
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 403);
      });
    });
  });
}

/// Le banc d'essai de la vente des livres.
final class _Harness {
  _Harness({
    required this.server,
    required this.database,
    required this.issuer,
    required this.audit,
    required this.projects,
    required this.storage,
    required this.payments,
    required this.sales,
    required this.entitlements,
    required this.promoCodes,
    required this.webhook,
  });

  final HttpServer server;
  final SqliteDatabase database;
  final TestTokenIssuer issuer;
  final InMemoryAuditLog audit;
  final InMemoryProjectStore projects;
  final InMemoryObjectStorage storage;
  final StubPaymentGateway payments;
  final SqliteBookSaleStore sales;
  final SqliteEntitlementStore entitlements;
  final SqlitePromoCodeStore promoCodes;
  final StripeWebhookService webhook;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Démarre le banc d'essai.
  static Future<_Harness> start() async {
    final SqliteDatabase database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();

    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
    final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });

    final InMemoryAuditLog audit = InMemoryAuditLog();
    final InMemoryProjectStore projects = InMemoryProjectStore();
    final InMemoryObjectStorage storage = InMemoryObjectStorage();
    final StubPaymentGateway payments = StubPaymentGateway();
    final SqliteBookSaleStore sales = SqliteBookSaleStore(database);
    final SqliteEntitlementStore entitlements = SqliteEntitlementStore(
      database,
    );
    final SqlitePromoCodeStore promoCodes = SqlitePromoCodeStore(database);

    final AppDependencies dependencies = AppDependencies(
      projects: projects,
      sync: InMemorySyncStore(),
      audit: audit,
      comments: InMemoryCommentStore(),
      purge: InMemoryAccountPurgeStore(entries: audit.entries),
      ai: StubAiGateway(),
      payments: payments,
      storage: storage,
      keyValue: InMemoryKeyValueStore(),
      jwtVerifier: JwtVerifier(
        jwks: jwks,
        expectedIssuer: 'https://project.test/auth/v1',
      ),
      logger: Logger(level: LogLevel.warning),
      databaseProbe: const AlwaysHealthyProbe(),
      syncHub: SyncHub(),
      shutdown: () async {},
    );

    final BookSaleService books = BookSaleService(
      sales: sales,
      entitlements: entitlements,
      promoCodes: promoCodes,
      projects: projects,
      storage: storage,
      audit: audit,
    );
    final StripeWebhookService webhook = StripeWebhookService(
      database: InMemoryStripeEventDatabase(),
      quota: QuotaService(database: InMemoryQuotaDatabase()),
      audit: audit,
      secret: webhookSecret,
      bookSales: books,
    );

    final AppConfig config = testConfig();
    final Router router = Router();
    registerCheckoutRoutes(
      router,
      dependencies,
      config,
      sales: sales,
      entitlements: entitlements,
      promoCodes: promoCodes,
    );
    registerBookSaleRoutes(
      router,
      dependencies,
      config,
      sales: sales,
      entitlements: entitlements,
      promoCodes: promoCodes,
    );

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning),
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(
          authenticationMiddleware(verifier: dependencies.jwtVerifier),
        )
        .addHandler(router.call);

    final HttpServer server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    return _Harness(
      server: server,
      database: database,
      issuer: issuer,
      audit: audit,
      projects: projects,
      storage: storage,
      payments: payments,
      sales: sales,
      entitlements: entitlements,
      promoCodes: promoCodes,
      webhook: webhook,
    );
  }

  /// Arrête le banc d'essai.
  Future<void> stop() async {
    await server.close(force: true);
    await database.close();
  }

  /// L'en-tête d'authentification du compte [userId].
  Map<String, String> auth(String userId) {
    return <String, String>{
      'authorization': 'Bearer ${issuer.issue(userId: userId)}',
    };
  }

  /// L'en-tête d'authentification de l'administration.
  Map<String, String> adminAuth() {
    return <String, String>{
      'authorization':
          'Bearer ${issuer.issue(userId: 'admin-1', role: 'admin')}',
    };
  }

  /// Crée un livre possédé par [ownerId].
  Future<String> createProject(String ownerId) async {
    final ProjectRecord project = await projects.create(
      ownerId: ownerId,
      title: 'Le livre',
      synopsis: 'Un synopsis.',
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    // Le livre existe aussi dans le stockage objet : c'est le fichier que
    // l'acheteur telecharge apres avoir paye.
    await storage.put(
      key: 'exports/${project.id}/livre.epub',
      bytes: _epubBytes(),
      contentType: 'application/epub+zip',
    );
    return project.id;
  }

  /// Montre le livre [projectId] dans la vitrine publique.
  Future<void> showInShowcase(String projectId) async {
    final List<ProjectRecord> owned = await projects.listAll(
      userId: 'auteur-1',
    );
    final ProjectRecord project = owned
        .where((ProjectRecord record) => record.id == projectId)
        .first;
    await projects.update(
      project.copyWith(status: ManuscriptStatus.published, isPublic: true),
    );
  }

  /// Met le livre [projectId] en vente.
  Future<void> publish(
    String projectId, {
    required int priceInCents,
    BookSaleStatus status = BookSaleStatus.published,
    int? authorShare,
  }) async {
    final http.Response response = await put(
      '/v1/books/$projectId/sale',
      body: <String, Object?>{
        'price_cents': priceInCents,
        'currency': 'eur',
        'status': status.key,
        'author_share': ?authorShare,
      },
      headers: auth('auteur-1'),
    );
    if (response.statusCode != 200) {
      throw StateError('The sale could not be published: ${response.body}');
    }
  }

  /// Crée un code promo par l'administration.
  Future<void> createPromoCode({
    required String code,
    required PromoDiscountType discountType,
    required int value,
    int maxUses = 100,
    DateTime? expiresAt,
  }) async {
    final http.Response response = await post(
      '/v1/admin/promo-codes',
      body: <String, Object?>{
        'code': code,
        'discount_type': discountType.key,
        'value': value,
        'max_uses': maxUses,
        'expires_at': (expiresAt ?? DateTime.utc(2027, 1, 1)).toIso8601String(),
      },
      headers: adminAuth(),
    );
    if (response.statusCode != 201) {
      throw StateError('The promo code could not be created: ${response.body}');
    }
  }

  /// Commande le livre [projectId].
  Future<http.Response> bookCheckout(
    String projectId, {
    required Map<String, String> headers,
    Map<String, Object?> body = const <String, Object?>{},
  }) {
    return post(
      '/v1/checkout/book',
      body: <String, Object?>{
        'project_id': projectId,
        'success_url': 'https://app.test/merci',
        'cancel_url': 'https://app.test/abandon',
        ...body,
      },
      headers: headers,
    );
  }

  /// Livre le paiement d'un livre au webhook Stripe.
  Future<StripeWebhookResult> deliverBookPayment({
    required String eventId,
    required String userId,
    required String projectId,
    int amountTotal = 1200,
    String paymentStatus = 'paid',
  }) async {
    final String payload = jsonEncode(<String, Object?>{
      'id': eventId,
      'object': 'event',
      'type': 'checkout.session.completed',
      'created': 1700000000,
      'data': <String, Object?>{
        'object': <String, Object?>{
          'id': 'cs_test_$eventId',
          'object': 'checkout.session',
          'client_reference_id': userId,
          'payment_status': paymentStatus,
          'mode': 'payment',
          'amount_total': amountTotal,
          'metadata': <String, Object?>{
            'user_id': userId,
            'kind': 'book',
            'project_id': projectId,
          },
        },
      },
    });
    return webhook.handle(
      payload: utf8.encode(payload),
      signature: _signature(webhookSecret, payload),
    );
  }

  /// Le `data` d'une réponse.
  Map<String, dynamic> dataOf(http.Response response) {
    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return payload['data'] as Map<String, dynamic>;
  }

  /// L'erreur d'une réponse.
  Map<String, dynamic> errorOf(http.Response response) {
    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return payload['error'] as Map<String, dynamic>;
  }

  /// Effectue une requête GET.
  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.get(Uri.parse('$baseUrl$path'), headers: headers);
  }

  /// Effectue une requête POST.
  Future<http.Response> post(
    String path, {
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Effectue une requête PUT.
  Future<http.Response> put(
    String path, {
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.put(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }
}

/// L'en-tête de signature d'une livraison Stripe.
String _signature(String secret, String payload, {DateTime? at}) {
  final DateTime moment = at ?? DateTime.now().toUtc();
  final int timestamp = moment.millisecondsSinceEpoch ~/ 1000;
  final Hmac hmac = Hmac(sha256, utf8.encode(secret));
  final String signature = hmac
      .convert(utf8.encode('$timestamp.$payload'))
      .toString();
  return 't=$timestamp,v1=$signature';
}

/// Le contenu du fichier d'un livre, pour la suite de tests.
Uint8List _epubBytes() => Uint8List.fromList(<int>[1, 2, 3, 4]);
