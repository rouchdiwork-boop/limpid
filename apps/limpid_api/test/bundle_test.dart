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
  group('bundles', () {
    late _Harness harness;
    late String firstBook;
    late String secondBook;

    setUp(() async {
      harness = await _Harness.start();
      firstBook = await harness.createProject('auteur-1');
      secondBook = await harness.createProject('auteur-1');
    });

    tearDown(() async {
      await harness.stop();
    });

    group('creation', () {
      test('un bundle porte au moins deux livres', () async {
        final http.Response response = await harness.createBundle(<String>[
          firstBook,
        ], priceInCents: 1500);

        expect(response.statusCode, 400);
        expect(harness.errorOf(response)['message'], contains('project_ids'));
      });

      test('un bundle qui contient un livre pas en vente est refuse', () async {
        await harness.publish(firstBook, priceInCents: 1000);

        final http.Response response = await harness.createBundle(<String>[
          firstBook,
          secondBook,
        ], priceInCents: 1500);

        expect(response.statusCode, 400);
        expect(harness.errorOf(response)['message'], contains(secondBook));
      });

      test('un bundle qui melange les auteurs est refuse', () async {
        final String otherBook = await harness.createProject('auteur-2');
        await harness.publish(firstBook, priceInCents: 1000);
        await harness.publish(
          otherBook,
          priceInCents: 1000,
          ownerId: 'auteur-2',
        );

        final http.Response response = await harness.createBundle(<String>[
          firstBook,
          otherBook,
        ], priceInCents: 1500);

        // Le livre d'un autre auteur est introuvable : la reponse ne dit
        // pas a un tiers que le livre existe.
        expect(response.statusCode, 404);
      });

      test('un bundle qui repete un livre est refuse', () async {
        await harness.publish(firstBook, priceInCents: 1000);

        final http.Response response = await harness.createBundle(<String>[
          firstBook,
          firstBook,
        ], priceInCents: 1500);

        expect(response.statusCode, 400);
      });

      test('le bundle porte son titre, ses livres et son prix', () async {
        await harness.publish(firstBook, priceInCents: 1000);
        await harness.publish(secondBook, priceInCents: 1000);

        final http.Response response = await harness.createBundle(<String>[
          firstBook,
          secondBook,
        ], priceInCents: 1500);

        expect(response.statusCode, 201);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['title'], 'Les deux livres');
        expect(data['price_cents'], 1500);
        expect(data['currency'], 'eur');
        expect(data['is_published'], isFalse);
        expect(data['project_ids'], <String>[firstBook, secondBook]);
      });

      test('le bundle porte le titre de ses livres', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        // La vitrine ne montre que les livres publies : les deux livres du
        // bundle le sont.
        await harness.showInShowcase(firstBook);
        await harness.showInShowcase(secondBook);

        final http.Response response = await harness.get(
          '/v1/public/bundles/$bundleId',
        );

        expect(response.statusCode, 200);
        final List<dynamic> books =
            harness.dataOf(response)['books'] as List<dynamic>;
        expect(books, hasLength(2));
        expect((books.first as Map<String, dynamic>)['project_id'], firstBook);
        expect((books.first as Map<String, dynamic>)['title'], 'Le livre');
      });
    });

    group('mise en vente', () {
      test('le vendeur met son bundle en vente', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publish(secondBook, priceInCents: 1000);

        final http.Response response = await harness.publishBundle(bundleId);

        expect(response.statusCode, 200);
        expect(harness.dataOf(response)['is_published'], isTrue);
      });

      test('un autre compte ne publie pas le bundle', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );

        final http.Response response = await harness.publishBundle(
          bundleId,
          headers: harness.auth('auteur-2'),
        );

        expect(response.statusCode, 403);
      });

      test('le bundle se lit sans compte quand il est en vente', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);

        final http.Response response = await harness.get(
          '/v1/public/bundles/$bundleId',
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['price_cents'], 1500);
        expect(data['project_ids'], hasLength(2));
        // Le vendeur reste sur le serveur : un lecteur n'a pas a le connaitre.
        expect(data.containsKey('owner_id'), isFalse);
      });

      test('un bundle non publie n\'a pas de prix public', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );

        final http.Response response = await harness.get(
          '/v1/public/bundles/$bundleId',
        );

        expect(response.statusCode, 404);
      });
    });

    group('commande', () {
      test('un bundle non publie n\'est pas achetable', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );

        final http.Response response = await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 409);
        expect(harness.payments.bundleRequests, isEmpty);
      });

      test('un bundle inconnu n\'est pas achetable', () async {
        final http.Response response = await harness.bundleCheckout(
          'bundle-inconnu',
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 404);
        expect(harness.payments.bundleRequests, isEmpty);
      });

      test('la commande porte le prix du bundle', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);

        final http.Response response = await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['price_cents'], 1500);
        expect(data['amount_cents'], 1500);
        expect(data['is_free'], isFalse);
        expect(data['granted'], isFalse);
        expect(harness.payments.bundleRequests, hasLength(1));
        expect(harness.payments.bundleRequests.single.priceInCents, 1500);
      });
    });

    group('droit de lecture', () {
      test('l\'achat d\'un bundle donne le droit sur chaque livre', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_1',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );

        for (final String projectId in <String>[firstBook, secondBook]) {
          final EntitlementRecord? entitlement = await harness.entitlements
              .find(userId: 'acheteur-1', projectId: projectId);
          expect(entitlement, isNotNull);
          expect(entitlement!.bundleId, bundleId);
        }
      });

      test('le meme paiement ne cree pas deux fois les droits', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_2',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );
        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_3',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );

        final List<EntitlementRecord> owned = await harness.entitlements
            .listByUser('acheteur-1');
        expect(owned, hasLength(2));
      });

      test('un bundle gratuit accorde les droits sans ventiler', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
          priceInCents: 0,
        );
        await harness.publishBundle(bundleId);

        final http.Response response = await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        expect(response.statusCode, 200);
        expect(harness.dataOf(response)['is_free'], isTrue);
        expect(harness.dataOf(response)['granted'], isTrue);
        // Aucun paiement n'est demande pour un bundle gratuit.
        expect(harness.payments.bundleRequests, isEmpty);

        for (final String projectId in <String>[firstBook, secondBook]) {
          final EntitlementRecord? entitlement = await harness.entitlements
              .find(userId: 'acheteur-1', projectId: projectId);
          expect(entitlement, isNotNull);
          expect(entitlement!.amountInCents, 0);
          expect(entitlement.authorAmountInCents, 0);
        }
      });

      test(
        'les livres achetes montrent le bundle dans leur provenance',
        () async {
          final String bundleId = await harness.sellableBundle(
            firstBook,
            secondBook,
          );
          await harness.publishBundle(bundleId);
          await harness.bundleCheckout(
            bundleId,
            headers: harness.auth('acheteur-1'),
          );
          await harness.deliverBundlePayment(
            eventId: 'evt_bundle_4',
            userId: 'acheteur-1',
            bundleId: bundleId,
            amountTotal: 1500,
          );

          final http.Response response = await harness.get(
            '/v1/purchases',
            headers: harness.auth('acheteur-1'),
          );

          expect(response.statusCode, 200);
          final List<dynamic> data = harness.listOf(response);
          expect(data, hasLength(2));
          for (final dynamic purchase in data) {
            final Map<String, dynamic> line = purchase as Map<String, dynamic>;
            expect(line['bundle_id'], bundleId);
            expect(line['bundle_title'], 'Les deux livres');
          }
        },
      );
    });

    group('ventilation', () {
      test('la ventilation suit la regle de la vente d\'un livre', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_5',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );

        final EntitlementRecord entitlement = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: firstBook,
        ))!;
        expect(entitlement.authorShare, 9000);
        expect(entitlement.platformShare, 1000);
        expect(
          entitlement.authorAmountInCents + entitlement.platformAmountInCents,
          entitlement.amountInCents,
        );
      });

      test('la ventilation est au prorata de chaque livre', () async {
        // Le premier livre vaut 1000, le second 500 : le premier recoit les
        // deux tiers du montant paye.
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
          secondPriceInCents: 500,
        );
        await harness.publishBundle(bundleId);
        await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_6',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );

        final EntitlementRecord heavy = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: firstBook,
        ))!;
        final EntitlementRecord light = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: secondBook,
        ))!;
        expect(heavy.amountInCents, 1000);
        expect(light.amountInCents, 500);
        expect(heavy.amountInCents + light.amountInCents, 1500);
      });

      test('la ventilation se fait sur le montant apres remise', () async {
        await harness.createPromoCode(
          code: 'BIENVENUE',
          discountType: PromoDiscountType.percent,
          value: 2500,
        );
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);

        final http.Response response = await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'BIENVENUE'},
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        expect(data['discount_cents'], 375);
        expect(data['amount_cents'], 1125);
        expect(harness.payments.bundleRequests.single.priceInCents, 1125);

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_7',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1125,
        );

        final EntitlementRecord heavy = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: firstBook,
        ))!;
        final EntitlementRecord light = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: secondBook,
        ))!;
        // La ventilation porte sur le montant paye : la remise ne sort pas
        // de la poche de l'auteur, et les deux lignes se partagent le
        // montant restant.
        expect(heavy.amountInCents + light.amountInCents, 1125);
        expect(
          heavy.authorAmountInCents + heavy.platformAmountInCents,
          heavy.amountInCents,
        );
        expect(
          light.authorAmountInCents + light.platformAmountInCents,
          light.amountInCents,
        );
      });

      test('la part configuree sur un livre est appliquee', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publish(firstBook, priceInCents: 1000, authorShare: 7000);
        await harness.publishBundle(bundleId);
        await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
        );

        await harness.deliverBundlePayment(
          eventId: 'evt_bundle_8',
          userId: 'acheteur-1',
          bundleId: bundleId,
          amountTotal: 1500,
        );

        final EntitlementRecord entitlement = (await harness.entitlements.find(
          userId: 'acheteur-1',
          projectId: firstBook,
        ))!;
        expect(entitlement.authorShare, 7000);
        // Le livre recoit la moitie du montant paye, et la part configuree
        // s'y applique comme dans une vente simple.
        expect(entitlement.amountInCents, 750);
        expect(entitlement.authorAmountInCents, 525);
        expect(entitlement.platformAmountInCents, 225);
      });
    });

    group('les garde-fous de la commande', () {
      test(
        'une adresse de retour hors des origines autorisées est refusée',
        () async {
          final String bundleId = await harness.sellableBundle(
            firstBook,
            secondBook,
          );
          await harness.publishBundle(bundleId);

          final http.Response response = await harness.bundleCheckout(
            bundleId,
            headers: harness.auth('acheteur-1'),
            body: <String, Object?>{
              'success_url': 'https://site-tiers.test/merci',
            },
          );

          expect(response.statusCode, 400);
          // La session n'a pas ete ouverte : rien n'a ete commande.
          expect(harness.payments.bundleRequests, isEmpty);
        },
      );

      test(
        'la reservation du code promo est rendue quand la session echoue',
        () async {
          final String bundleId = await harness.sellableBundle(
            firstBook,
            secondBook,
          );
          await harness.publishBundle(bundleId);
          await harness.createPromoCode(
            code: 'WELCOME10',
            discountType: PromoDiscountType.amount,
            value: 1000,
          );

          harness.payments.nextError = const ServiceUnavailableException(
            message: 'Le prestataire de paiement ne repond pas.',
          );
          final http.Response response = await harness.bundleCheckout(
            bundleId,
            headers: harness.auth('acheteur-1'),
            body: <String, Object?>{'promo_code': 'WELCOME10'},
          );

          expect(response.statusCode, 503);
          // La commande a echoue : la place prise par le code est rendue,
          // sinon le code s'epuise sur des commandes qui n'ont pas abouti.
          final PromoCodeRecord? code = await harness.promoCodes.findByCode(
            'WELCOME10',
          );
          expect(code?.uses, 0);
        },
      );

      test('une session expiree rend la reservation du code promo', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        await harness.createPromoCode(
          code: 'WELCOME10',
          discountType: PromoDiscountType.amount,
          value: 1000,
        );

        final http.Response response = await harness.bundleCheckout(
          bundleId,
          headers: harness.auth('acheteur-1'),
          body: <String, Object?>{'promo_code': 'WELCOME10'},
        );
        expect(response.statusCode, 200);

        final PromoCodeRecord? reserved = await harness.promoCodes.findByCode(
          'WELCOME10',
        );
        expect(reserved?.uses, 1);

        await harness.deliverExpiredCheckout(
          eventId: 'evt_bundle_expire',
          userId: 'acheteur-1',
          promoCode: 'WELCOME10',
        );

        final PromoCodeRecord? released = await harness.promoCodes.findByCode(
          'WELCOME10',
        );
        expect(released?.uses, 0);
      });

      test('un livre qui n est pas dans la vitrine n apparait pas', () async {
        final String bundleId = await harness.sellableBundle(
          firstBook,
          secondBook,
        );
        await harness.publishBundle(bundleId);
        // Le premier livre est dans la vitrine, le second est en vente
        // mais son auteur ne l'a pas publie.
        await harness.showInShowcase(firstBook);

        final http.Response response = await harness.get(
          '/v1/public/bundles/$bundleId',
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = harness.dataOf(response);
        final List<dynamic> books = data['books'] as List<dynamic>;
        final List<String> ids = books
            .map(
              (dynamic book) =>
                  (book as Map<String, dynamic>)['project_id']! as String,
            )
            .toList();
        expect(ids, <String>[firstBook]);
        expect(ids, isNot(contains(secondBook)));
      });
    });
  });
}

/// Le banc d'essai des bundles.
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
    required this.bundles,
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
  final SqliteBundleStore bundles;
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
    final SqliteBundleStore bundles = SqliteBundleStore(database);

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
    final BundleService bundleService = BundleService(
      bundles: bundles,
      books: books,
      audit: audit,
    );
    final StripeWebhookService webhook = StripeWebhookService(
      database: InMemoryStripeEventDatabase(),
      quota: QuotaService(database: InMemoryQuotaDatabase()),
      audit: audit,
      secret: webhookSecret,
      bookSales: books,
      bundles: bundleService,
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
      bundles: bundles,
    );
    registerBundleRoutes(
      router,
      dependencies,
      config,
      bundles: bundles,
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
      bundles: bundles,
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
    await storage.put(
      key: 'exports/${project.id}/livre.epub',
      bytes: _epubBytes(),
      contentType: 'application/epub+zip',
    );
    return project.id;
  }

  /// Met le livre [projectId] en vente.
  Future<void> publish(
    String projectId, {
    required int priceInCents,
    int? authorShare,
    String ownerId = 'auteur-1',
  }) async {
    final http.Response response = await put(
      '/v1/books/$projectId/sale',
      body: <String, Object?>{
        'price_cents': priceInCents,
        'currency': 'eur',
        'author_share': ?authorShare,
      },
      headers: auth(ownerId),
    );
    if (response.statusCode != 200) {
      throw StateError('The sale could not be published: ${response.body}');
    }
  }

  /// Crée un bundle.
  Future<http.Response> createBundle(
    List<String> projectIds, {
    required int priceInCents,
  }) {
    return post(
      '/v1/bundles',
      body: <String, Object?>{
        'title': 'Les deux livres',
        'description': 'Un ensemble.',
        'project_ids': projectIds,
        'price_cents': priceInCents,
        'currency': 'eur',
      },
      headers: auth('auteur-1'),
    );
  }

  /// Crée un bundle dont les deux livres sont en vente.
  Future<String> sellableBundle(
    String firstBook,
    String secondBook, {
    int priceInCents = 1500,
    int secondPriceInCents = 1000,
  }) async {
    await publish(firstBook, priceInCents: 1000);
    await publish(secondBook, priceInCents: secondPriceInCents);
    final http.Response response = await createBundle(<String>[
      firstBook,
      secondBook,
    ], priceInCents: priceInCents);
    if (response.statusCode != 201) {
      throw StateError('The bundle could not be created: ${response.body}');
    }
    return dataOf(response)['id']! as String;
  }

  /// Met le bundle [bundleId] en vente.
  Future<http.Response> publishBundle(
    String bundleId, {
    Map<String, String>? headers,
  }) {
    return put(
      '/v1/bundles/$bundleId/publication',
      body: <String, Object?>{'is_published': true},
      headers: headers ?? auth('auteur-1'),
    );
  }

  /// Crée un code promo par l'administration.
  Future<void> createPromoCode({
    required String code,
    required PromoDiscountType discountType,
    required int value,
    int maxUses = 100,
  }) async {
    final http.Response response = await post(
      '/v1/admin/promo-codes',
      body: <String, Object?>{
        'code': code,
        'discount_type': discountType.key,
        'value': value,
        'max_uses': maxUses,
        'expires_at': DateTime.utc(2027, 1, 1).toIso8601String(),
      },
      headers: adminAuth(),
    );
    if (response.statusCode != 201) {
      throw StateError('The promo code could not be created: ${response.body}');
    }
  }

  /// Commande le bundle [bundleId].
  Future<http.Response> bundleCheckout(
    String bundleId, {
    required Map<String, String> headers,
    Map<String, Object?> body = const <String, Object?>{},
  }) {
    return post(
      '/v1/checkout/bundle',
      body: <String, Object?>{
        'bundle_id': bundleId,
        'success_url': 'https://app.test/merci',
        'cancel_url': 'https://app.test/abandon',
        ...body,
      },
      headers: headers,
    );
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

  /// Livre l'expiration d'une session de paiement au webhook Stripe.
  ///
  /// L'expiration ne rend aucun droit : elle rend la place qu'une commande
  /// avait prise sur un code promo.
  Future<StripeWebhookResult> deliverExpiredCheckout({
    required String eventId,
    required String userId,
    required String promoCode,
  }) async {
    final String payload = jsonEncode(<String, Object?>{
      'id': eventId,
      'object': 'event',
      'type': 'checkout.session.expired',
      'created': 1700000000,
      'data': <String, Object?>{
        'object': <String, Object?>{
          'id': 'cs_test_$eventId',
          'object': 'checkout.session',
          'client_reference_id': userId,
          'payment_status': 'unpaid',
          'mode': 'payment',
          'metadata': <String, Object?>{
            'user_id': userId,
            'kind': 'bundle',
            'promo_code': promoCode,
          },
        },
      },
    });
    return webhook.handle(
      payload: utf8.encode(payload),
      signature: _signature(webhookSecret, payload),
    );
  }

  /// Livre le paiement d'un bundle au webhook Stripe.
  Future<StripeWebhookResult> deliverBundlePayment({
    required String eventId,
    required String userId,
    required String bundleId,
    int amountTotal = 1500,
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
            'kind': 'bundle',
            'bundle_id': bundleId,
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

  /// La liste `data` d'une réponse.
  List<dynamic> listOf(http.Response response) {
    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return payload['data'] as List<dynamic>;
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
