import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/audit_entry.dart';
import 'package:limpid_api/src/db/audit_log.dart';
import 'package:limpid_api/src/db/in_memory_quota_database.dart';
import 'package:limpid_api/src/db/in_memory_stripe_event_database.dart';
import 'package:limpid_api/src/db/quota_database.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:limpid_api/src/db/sqlite_stripe_event_database.dart';
import 'package:limpid_api/src/errors/app_exception.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/stripe_webhook_routes.dart';
import 'package:limpid_api/src/services/quota_service.dart';
import 'package:limpid_api/src/services/stripe_webhook_service.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

/// Le secret du point de rappel Stripe, dans la suite de tests.
const String webhookSecret = 'whsec_secret_de_test';

void main() {
  group('webhook Stripe', () {
    group('signature', () {
      test('une signature valide est acceptée', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_1',
          userId: 'user-1',
        );

        final StripeWebhookResult result = await webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(webhookSecret, payload),
        );

        expect(result.outcome, StripeWebhookOutcome.applied);
      });

      test('une signature invalide est refusée', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_2',
          userId: 'user-1',
        );

        await expectLater(
          webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature('un-autre-secret', payload),
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(
          (await webhook.service.quota.planOf('user-1')).plan,
          SubscriptionPlan.free,
          reason: 'une livraison refusée ne touche aucune formule',
        );
      });

      test('un en-tête absent est refusé', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_3',
          userId: 'user-1',
        );

        await expectLater(
          webhook.service.handle(
            payload: utf8.encode(payload),
            signature: null,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('un horodatage hors tolérance est refusé', () async {
        final _Webhook webhook = _buildWebhook();
        final DateTime now = DateTime.now().toUtc();
        final String payload = _checkoutPayload(
          eventId: 'evt_4',
          userId: 'user-1',
        );

        final String stale = _signature(
          webhookSecret,
          payload,
          at: now.subtract(const Duration(minutes: 10)),
        );
        await expectLater(
          webhook.service.handle(
            payload: utf8.encode(payload),
            signature: stale,
          ),
          throwsA(isA<UnauthorizedException>()),
        );

        final String ahead = _signature(
          webhookSecret,
          payload,
          at: now.add(const Duration(minutes: 10)),
        );
        await expectLater(
          webhook.service.handle(
            payload: utf8.encode(payload),
            signature: ahead,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('un horodatage dans la tolérance est accepté', () async {
        final _Webhook webhook = _buildWebhook();
        final DateTime now = DateTime.now().toUtc();
        final String payload = _checkoutPayload(
          eventId: 'evt_5',
          userId: 'user-1',
        );

        final StripeWebhookResult result = await webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(
            webhookSecret,
            payload,
            at: now.subtract(const Duration(minutes: 4)),
          ),
        );

        expect(result.outcome, StripeWebhookOutcome.applied);
      });
    });

    group('attribution', () {
      test('un paiement confirmé attribue la formule payée', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_10',
          userId: 'user-1',
          plan: 'studio',
        );

        final StripeWebhookResult result = await webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(webhookSecret, payload),
        );

        expect(result.outcome, StripeWebhookOutcome.applied);
        expect(result.action, 'plan.payment_confirmed');
        final AccountPlan plan = await webhook.service.quota.planOf('user-1');
        expect(plan.plan, SubscriptionPlan.studio);
        expect(plan.period, BillingPeriod.monthly);
      });

      test('la trace porte la référence du paiement', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_11',
          userId: 'user-1',
          plan: 'pro',
        );

        await webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(webhookSecret, payload),
        );

        expect(webhook.audit.entries, hasLength(1));
        final AuditEntry entry = webhook.audit.entries.single;
        expect(entry.action, 'plan.payment_confirmed');
        expect(entry.userId, 'user-1');
        expect(entry.targetType, 'subscription');
        expect(entry.targetId, 'cs_test_evt_11');
        expect(entry.metadata['payment_reference'], 'cs_test_evt_11');
        expect(entry.metadata['plan'], 'pro');
      });

      test('un paiement non encaissé n\'attribue aucune formule', () async {
        final _Webhook webhook = _buildWebhook();
        final String payload = _checkoutPayload(
          eventId: 'evt_12',
          userId: 'user-1',
          paymentStatus: 'unpaid',
        );

        final StripeWebhookResult result = await webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(webhookSecret, payload),
        );

        expect(result.outcome, StripeWebhookOutcome.ignored);
        expect(
          (await webhook.service.quota.planOf('user-1')).plan,
          SubscriptionPlan.free,
        );
        expect(webhook.audit.entries, isEmpty);
      });

      test(
        'la formule gratuite n\'est jamais attribuée par un paiement',
        () async {
          final _Webhook webhook = _buildWebhook();
          final String payload = _checkoutPayload(
            eventId: 'evt_13',
            userId: 'user-1',
            plan: 'free',
          );

          final StripeWebhookResult result = await webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature(webhookSecret, payload),
          );

          expect(result.outcome, StripeWebhookOutcome.ignored);
          expect(
            (await webhook.service.quota.planOf('user-1')).plan,
            SubscriptionPlan.free,
          );
        },
      );

      test('un changement de formule applique la nouvelle formule', () async {
        final _Webhook webhook = _buildWebhook();
        final String payment = _checkoutPayload(
          eventId: 'evt_14',
          userId: 'user-1',
          plan: 'writer',
        );
        await webhook.service.handle(
          payload: utf8.encode(payment),
          signature: _signature(webhookSecret, payment),
        );

        final String change = _subscriptionUpdatedPayload(
          eventId: 'evt_15',
          userId: 'user-1',
          plan: 'pro',
        );
        final StripeWebhookResult result = await webhook.service.handle(
          payload: utf8.encode(change),
          signature: _signature(webhookSecret, change),
        );

        expect(result.outcome, StripeWebhookOutcome.applied);
        expect(result.action, 'plan.subscription_changed');
        final AccountPlan plan = await webhook.service.quota.planOf('user-1');
        expect(plan.plan, SubscriptionPlan.pro);
        expect(webhook.audit.entries.last.action, 'plan.subscription_changed');
      });

      test('un changement de formule ne rend pas l\'essai', () async {
        final _Webhook webhook = _buildWebhook();
        await webhook.service.quota.changePlan(
          userId: 'user-1',
          plan: SubscriptionPlan.writer,
          period: BillingPeriod.monthly,
          startTrial: true,
        );
        final AccountPlan trial = await webhook.service.quota.planOf('user-1');
        expect(trial.isInTrial(DateTime.now().toUtc()), isTrue);

        final String change = _subscriptionUpdatedPayload(
          eventId: 'evt_16',
          userId: 'user-1',
          plan: 'pro',
        );
        await webhook.service.handle(
          payload: utf8.encode(change),
          signature: _signature(webhookSecret, change),
        );

        final AccountPlan plan = await webhook.service.quota.planOf('user-1');
        expect(plan.plan, SubscriptionPlan.pro);
        expect(plan.trialEndsAt, isNull);
        expect(plan.hasConsumedTrial, isTrue);
      });

      test(
        'un abonnement résilié ramène le compte à la formule gratuite',
        () async {
          final _Webhook webhook = _buildWebhook();
          final String payment = _checkoutPayload(
            eventId: 'evt_17',
            userId: 'user-1',
            plan: 'studio',
          );
          await webhook.service.handle(
            payload: utf8.encode(payment),
            signature: _signature(webhookSecret, payment),
          );

          final String cancellation = _subscriptionDeletedPayload(
            eventId: 'evt_18',
            userId: 'user-1',
          );
          final StripeWebhookResult result = await webhook.service.handle(
            payload: utf8.encode(cancellation),
            signature: _signature(webhookSecret, cancellation),
          );

          expect(result.outcome, StripeWebhookOutcome.applied);
          expect(result.action, 'plan.subscription_cancelled');
          final AccountPlan plan = await webhook.service.quota.planOf('user-1');
          expect(plan.plan, SubscriptionPlan.free);
          expect(
            webhook.audit.entries.last.action,
            'plan.subscription_cancelled',
          );
        },
      );
    });

    group('idempotence', () {
      test(
        'un événement rejoué n\'applique pas l\'effet une seconde fois',
        () async {
          final _Webhook webhook = _buildWebhook();
          final String payload = _checkoutPayload(
            eventId: 'evt_20',
            userId: 'user-1',
            plan: 'pro',
          );

          final StripeWebhookResult first = await webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature(webhookSecret, payload),
          );
          final StripeWebhookResult second = await webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature(webhookSecret, payload),
          );

          expect(first.outcome, StripeWebhookOutcome.applied);
          expect(second.outcome, StripeWebhookOutcome.replayed);
          expect(webhook.audit.entries, hasLength(1));
          expect(webhook.events.length, 1);
        },
      );

      test(
        'un événement rejoué ne rend pas l\'essai une seconde fois',
        () async {
          final _Webhook webhook = _buildWebhook();
          final String payload = _checkoutPayload(
            eventId: 'evt_21',
            userId: 'user-1',
            plan: 'pro',
          );

          await webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature(webhookSecret, payload),
          );
          await webhook.service.handle(
            payload: utf8.encode(payload),
            signature: _signature(webhookSecret, payload),
          );

          final AccountPlan plan = await webhook.service.quota.planOf('user-1');
          expect(plan.plan, SubscriptionPlan.pro);
          expect(plan.trialEndsAt, isNull);
        },
      );

      test('la réservation d\'un événement est atomique en SQLite', () async {
        final SqliteDatabase database = await SqliteDatabase.openInMemory();
        addTearDown(database.close);
        await SqliteMigrationRunner(
          database: database,
          directory: 'db/migrations/sqlite',
        ).run();
        final SqliteStripeEventDatabase events = SqliteStripeEventDatabase(
          database,
        );
        final DateTime now = DateTime.now().toUtc();

        expect(
          await events.claimEvent(
            eventId: 'evt_30',
            type: 'checkout.session.completed',
            processedAt: now,
          ),
          isTrue,
        );
        expect(
          await events.claimEvent(
            eventId: 'evt_30',
            type: 'checkout.session.completed',
            processedAt: now,
          ),
          isFalse,
        );
        expect(
          (await events.eventOf('evt_30'))?.type,
          'checkout.session.completed',
        );

        await events.releaseEvent('evt_30');
        expect(
          await events.claimEvent(
            eventId: 'evt_30',
            type: 'checkout.session.completed',
            processedAt: now,
          ),
          isTrue,
        );
      });
    });

    group('route', () {
      test('la route accepte une livraison valide', () async {
        final _Webhook webhook = _buildWebhook();
        final _WebhookServer server = await _serve(webhook);
        addTearDown(server.stop);
        final String payload = _checkoutPayload(
          eventId: 'evt_40',
          userId: 'user-1',
          plan: 'pro',
        );

        final http.Response response = await _post(
          server,
          payload,
          _signature(webhookSecret, payload),
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
        expect(data['outcome'], 'applied');
        expect(data['event_id'], 'evt_40');
        expect(
          (await webhook.service.quota.planOf('user-1')).plan,
          SubscriptionPlan.pro,
        );
      });

      test('la route refuse une signature invalide', () async {
        final _Webhook webhook = _buildWebhook();
        final _WebhookServer server = await _serve(webhook);
        addTearDown(server.stop);
        final String payload = _checkoutPayload(
          eventId: 'evt_41',
          userId: 'user-1',
        );

        final http.Response response = await _post(
          server,
          payload,
          _signature('un-autre-secret', payload),
        );

        expect(response.statusCode, 401);
        expect(
          (await webhook.service.quota.planOf('user-1')).plan,
          SubscriptionPlan.free,
        );
      });

      test(
        'la route répond un refus propre quand le secret est absent',
        () async {
          final _Webhook webhook = _buildWebhook(secret: null);
          final _WebhookServer server = await _serve(webhook);
          addTearDown(server.stop);
          final String payload = _checkoutPayload(
            eventId: 'evt_42',
            userId: 'user-1',
          );

          final http.Response response = await _post(
            server,
            payload,
            _signature(webhookSecret, payload),
          );

          expect(response.statusCode, 503);
          expect(
            (await webhook.service.quota.planOf('user-1')).plan,
            SubscriptionPlan.free,
          );
        },
      );

      test('la route ne demande pas de jeton de session', () async {
        final _Webhook webhook = _buildWebhook();
        final _WebhookServer server = await _serve(webhook);
        addTearDown(server.stop);
        final String payload = _checkoutPayload(
          eventId: 'evt_43',
          userId: 'user-1',
        );

        // Aucune en-tête d'authentification : la signature suffit.
        final http.Response response = await _post(
          server,
          payload,
          _signature(webhookSecret, payload),
        );

        expect(response.statusCode, 200);
      });

      test('la route refuse un corps trop grand', () async {
        final _Webhook webhook = _buildWebhook();
        final _WebhookServer server = await _serve(
          webhook,
          config: _config(maxBodyBytes: 64),
        );
        addTearDown(server.stop);
        final String payload = _checkoutPayload(
          eventId: 'evt_44',
          userId: 'user-1',
        );

        final http.Response response = await _post(
          server,
          payload,
          _signature(webhookSecret, payload),
        );

        expect(response.statusCode, 413);
      });
    });

    test('le corps de la livraison n\'est jamais journalisé', () async {
      final _Webhook webhook = _buildWebhook();
      final String payload = _checkoutPayload(
        eventId: 'evt_50',
        userId: 'user-1',
        cardNumber: '4242424242424242',
      );

      await webhook.service.handle(
        payload: utf8.encode(payload),
        signature: _signature(webhookSecret, payload),
      );

      expect(webhook.logLines, isNotEmpty);
      for (final String line in webhook.logLines) {
        expect(line, isNot(contains('4242424242424242')));
        expect(line, isNot(contains(payload)));
      }
      // La trace d'audit porte la référence du paiement, jamais les données
      // de la carte.
      expect(webhook.audit.entries, hasLength(1));
      expect(
        jsonEncode(webhook.audit.entries.single.toJson()),
        isNot(contains('4242424242424242')),
      );
    });

    test('un événement sans compte est ignoré', () async {
      final _Webhook webhook = _buildWebhook();
      final String payload = jsonEncode(<String, Object?>{
        'id': 'evt_51',
        'object': 'event',
        'type': 'checkout.session.completed',
        'data': <String, Object?>{
          'object': <String, Object?>{
            'id': 'cs_test_evt_51',
            'payment_status': 'paid',
          },
        },
      });

      final StripeWebhookResult result = await webhook.service.handle(
        payload: utf8.encode(payload),
        signature: _signature(webhookSecret, payload),
      );

      expect(result.outcome, StripeWebhookOutcome.ignored);
      expect(webhook.audit.entries, isEmpty);
    });

    test('un événement hors abonnement est ignoré', () async {
      final _Webhook webhook = _buildWebhook();
      final String payload = jsonEncode(<String, Object?>{
        'id': 'evt_52',
        'object': 'event',
        'type': 'invoice.created',
        'data': <String, Object?>{
          'object': <String, Object?>{'id': 'in_test_1'},
        },
      });

      final StripeWebhookResult result = await webhook.service.handle(
        payload: utf8.encode(payload),
        signature: _signature(webhookSecret, payload),
      );

      expect(result.outcome, StripeWebhookOutcome.ignored);
      expect(webhook.events.length, 0);
    });

    test('un corps qui n\'est pas un JSON est refusé', () async {
      final _Webhook webhook = _buildWebhook();
      const String payload = 'ceci n\'est pas un JSON';

      await expectLater(
        webhook.service.handle(
          payload: utf8.encode(payload),
          signature: _signature(webhookSecret, payload),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    group('configuration', () {
      test('le secret et les événements se lisent dans l\'environnement', () {
        final AppConfig config = AppConfig.fromEnvironment(<String, String>{
          'PORT': '0',
          'SUPABASE_URL': 'https://project.test',
          'SUPABASE_ANON_KEY': 'test-anon-key',
          'STRIPE_WEBHOOK_SECRET': 'whsec_de_l_environnement',
          'STRIPE_WEBHOOK_EVENTS':
              'checkout.session.completed, '
              'customer.subscription.deleted',
        });

        expect(config.stripeWebhookSecret, 'whsec_de_l_environnement');
        expect(config.stripeWebhookEvents, <String>[
          'checkout.session.completed',
          'customer.subscription.deleted',
        ]);
      });

      test('un secret absent ne fait pas échouer la configuration', () {
        final AppConfig config = AppConfig.fromEnvironment(<String, String>{
          'PORT': '0',
          'SUPABASE_URL': 'https://project.test',
          'SUPABASE_ANON_KEY': 'test-anon-key',
        });

        expect(config.stripeWebhookSecret, isNull);
        expect(config.stripeWebhookEvents, isEmpty);
      });

      test('une liste d\'événements inconnue ne désactive pas le webhook', () {
        final StripeWebhookService service = StripeWebhookService(
          database: InMemoryStripeEventDatabase(),
          quota: QuotaService(database: InMemoryQuotaDatabase()),
          audit: _AuditLog(),
          secret: webhookSecret,
          handledEvents: const <String>['evenement.inconnu'],
        );

        expect(service.handledEvents, contains('checkout.session.completed'));
      });
    });
  });
}

/// Le journal d'audit tenu en mémoire, pour la suite de tests.
final class _AuditLog implements AuditLog {
  final List<AuditEntry> entries = <AuditEntry>[];

  @override
  Future<void> record(AuditEntry entry) async {
    entries.add(entry);
  }

  @override
  Future<List<AuditEntry>> entriesOf({
    required String userId,
    required int limit,
    String? action,
  }) async {
    return entries
        .where(
          (AuditEntry entry) =>
              entry.userId == userId &&
              (action == null || entry.action == action),
        )
        .take(limit)
        .toList(growable: false);
  }
}

/// Le banc d'essai du webhook Stripe.
final class _Webhook {
  const _Webhook({
    required this.service,
    required this.audit,
    required this.events,
    required this.logLines,
  });

  /// Le service du webhook.
  final StripeWebhookService service;

  /// Le journal d'audit.
  final _AuditLog audit;

  /// La table des événements traités.
  final InMemoryStripeEventDatabase events;

  /// Les lignes écrites par le journal du serveur.
  final List<String> logLines;
}

/// Construit un banc d'essai du webhook Stripe.
_Webhook _buildWebhook({String? secret = webhookSecret}) {
  final InMemoryQuotaDatabase quotas = InMemoryQuotaDatabase();
  final _AuditLog audit = _AuditLog();
  final InMemoryStripeEventDatabase events = InMemoryStripeEventDatabase();
  final List<String> logLines = <String>[];
  final StripeWebhookService service = StripeWebhookService(
    database: events,
    quota: QuotaService(database: quotas),
    audit: audit,
    secret: secret,
    logger: Logger(level: LogLevel.debug, sink: logLines.add),
  );
  return _Webhook(
    service: service,
    audit: audit,
    events: events,
    logLines: logLines,
  );
}

/// La configuration du banc d'essai.
AppConfig _config({int maxBodyBytes = 4 * 1024 * 1024}) {
  return AppConfig.fromEnvironment(<String, String>{
    'PORT': '0',
    'SUPABASE_URL': 'https://project.test',
    'SUPABASE_ANON_KEY': 'test-anon-key',
    'MAX_BODY_BYTES': '$maxBodyBytes',
  });
}

/// Le serveur qui ne sert que la route du webhook Stripe.
final class _WebhookServer {
  const _WebhookServer(this._server);

  final HttpServer _server;

  /// L'adresse du serveur.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// Arrête le serveur.
  Future<void> stop() => _server.close(force: true);
}

/// Sert la route du webhook Stripe.
Future<_WebhookServer> _serve(_Webhook webhook, {AppConfig? config}) async {
  final Router router = Router();
  registerStripeWebhookRoutes(router, webhook.service, config ?? _config());
  final Handler handler = const Pipeline()
      .addMiddleware(
        errorHandlerMiddleware(
          logger: Logger(level: LogLevel.error, sink: (String _) {}),
        ),
      )
      .addHandler(router.call);
  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    0,
  );
  return _WebhookServer(server);
}

/// Envoie une livraison Stripe au serveur.
Future<http.Response> _post(
  _WebhookServer server,
  String payload,
  String signature,
) {
  return http.post(
    Uri.parse('${server.baseUrl}/v1/stripe/webhook'),
    headers: <String, String>{
      'content-type': 'application/json',
      'stripe-signature': signature,
    },
    body: payload,
  );
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

/// Le corps d'une livraison de paiement.
String _checkoutPayload({
  required String eventId,
  required String userId,
  String plan = 'pro',
  String paymentStatus = 'paid',
  String? cardNumber,
}) {
  return jsonEncode(<String, Object?>{
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
        'mode': 'subscription',
        'metadata': <String, Object?>{'user_id': userId, 'plan': plan},
        if (cardNumber != null)
          'payment_method_details': <String, Object?>{
            'card': <String, Object?>{'last4': cardNumber, 'brand': 'visa'},
          },
      },
    },
  });
}

/// Le corps d'une livraison de changement de formule.
String _subscriptionUpdatedPayload({
  required String eventId,
  required String userId,
  String plan = 'pro',
}) {
  return jsonEncode(<String, Object?>{
    'id': eventId,
    'object': 'event',
    'type': 'customer.subscription.updated',
    'created': 1700000000,
    'data': <String, Object?>{
      'object': <String, Object?>{
        'id': 'sub_test_$eventId',
        'object': 'subscription',
        'customer': 'cus_test',
        'status': 'active',
        'metadata': <String, Object?>{'user_id': userId, 'plan': plan},
      },
    },
  });
}

/// Le corps d'une livraison de résiliation.
String _subscriptionDeletedPayload({
  required String eventId,
  required String userId,
}) {
  return jsonEncode(<String, Object?>{
    'id': eventId,
    'object': 'event',
    'type': 'customer.subscription.deleted',
    'created': 1700000000,
    'data': <String, Object?>{
      'object': <String, Object?>{
        'id': 'sub_test_$eventId',
        'object': 'subscription',
        'customer': 'cus_test',
        'status': 'canceled',
        'metadata': <String, Object?>{'user_id': userId},
      },
    },
  });
}
