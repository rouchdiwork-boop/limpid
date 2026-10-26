import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/audit_entry.dart';
import 'package:limpid_api/src/db/in_memory_export_job_store.dart';
import 'package:limpid_api/src/db/in_memory_quota_database.dart';
import 'package:limpid_api/src/db/quota_database.dart';
import 'package:limpid_api/src/db/sql_quota_database.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:limpid_api/src/errors/app_exception.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/export_routes.dart';
import 'package:limpid_api/src/routes/quota_routes.dart';
import 'package:limpid_api/src/services/export_service.dart';
import 'package:limpid_api/src/services/plan_catalog.dart';
import 'package:limpid_api/src/services/quota_service.dart';
import 'package:limpid_api/src/worker/export_worker.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_server.dart';

void main() {
  _quotaContract(
    'base en mémoire',
    () async => _QuotaFixture(database: InMemoryQuotaDatabase()),
  );

  _quotaContract('base SQLite', () async {
    final SqliteDatabase database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();
    return _QuotaFixture(
      database: SqliteQuotaDatabase(database),
      dispose: database.close,
    );
  });

  group('routes des quotas', () {
    late InMemoryQuotaDatabase database;
    late InMemoryAuditLog audit;
    late Handler handler;

    setUp(() {
      database = InMemoryQuotaDatabase();
      audit = InMemoryAuditLog();
      final Router router = Router();
      registerQuotaRoutes(router, database, testConfig(), audit: audit);
      handler = _handler(router);
    });

    test('GET /v1/plans renvoie les quatre formules', () async {
      final Response response = await handler(_get('/v1/plans'));

      expect(response.statusCode, 200);
      final Map<String, dynamic> body = await _body(response);
      final List<dynamic> plans = body['data'] as List<dynamic>;
      expect(plans, hasLength(4));
      expect(
        plans
            .map((dynamic item) => (item as Map<String, dynamic>)['plan'])
            .toList(),
        <String>['free', 'writer', 'pro', 'studio'],
      );
    });

    test('GET /v1/me/plan décrit la formule du compte', () async {
      final Response response = await handler(_get('/v1/me/plan'));

      expect(response.statusCode, 200);
      final Map<String, dynamic> body = await _body(response);
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['plan'], 'free');
      expect(data['status'], 'free');
      expect(data['period'], 'monthly');
    });

    test('GET /v1/me/quota liste les compteurs et leurs limites', () async {
      final Response response = await handler(_get('/v1/me/quota'));

      expect(response.statusCode, 200);
      final Map<String, dynamic> body = await _body(response);
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      final List<dynamic> quotas = data['quotas'] as List<dynamic>;
      expect(quotas, hasLength(QuotaFeature.values.length));

      final Map<String, dynamic> exports = quotas
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (Map<String, dynamic> item) => item['feature'] == 'exports',
          );
      expect(exports['limit'], 50);
      expect(exports['used'], 0);
      expect(exports['period'], 'month');
    });

    test('POST /v1/me/plan change la formule et trace l\'action', () async {
      final Response response = await handler(
        _post('/v1/me/plan', <String, Object?>{
          'plan': 'writer',
          'start_trial': true,
        }),
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body = await _body(response);
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['plan'], 'writer');
      expect(data['trial_ends_at'], isNotNull);

      expect(audit.entries, hasLength(1));
      final AuditEntry entry = audit.entries.single;
      expect(entry.action, 'plan.changed');
      expect(entry.targetType, 'subscription');
      expect(entry.metadata['plan'], 'writer');
      expect(entry.metadata['previous_plan'], 'free');
    });

    test('POST /v1/me/plan refuse une formule inconnue', () async {
      final Response response = await handler(
        _post('/v1/me/plan', <String, Object?>{'plan': 'inexistante'}),
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> error = await _error(response);
      expect(error['code'], 'validation_failed');
      expect(audit.entries, isEmpty);
    });

    test('POST /v1/me/plan refuse le cycle annuel hors Studio', () async {
      final Response response = await handler(
        _post('/v1/me/plan', <String, Object?>{
          'plan': 'writer',
          'period': 'yearly',
        }),
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> error = await _error(response);
      expect(error['code'], 'validation_failed');
      expect(audit.entries, isEmpty);
    });

    test('POST /v1/me/plan refuse la formule quand l\'audit manque', () async {
      final Router router = Router();
      registerQuotaRoutes(router, database, testConfig());

      final Response response = await _handler(router)(
        _post('/v1/me/plan', <String, Object?>{'plan': 'writer'}),
      );

      expect(response.statusCode, 503);
      final Map<String, dynamic> error = await _error(response);
      expect(error['code'], 'service_unavailable');
    });
  });

  group('garde-fou de l\'export', () {
    late TestServer server;
    late InMemoryQuotaDatabase database;
    late DateTime now;
    late QuotaService quota;

    setUp(() async {
      server = await startTestServer();
      database = InMemoryQuotaDatabase();
      now = DateTime.utc(2026, 10, 26, 9);
      quota = QuotaService(database: database, clock: () => now);
    });

    tearDown(() async {
      await server.stop();
    });

    test('refuse l\'export quand le quota est atteint', () async {
      final String projectId = await _seedProject(server);
      await _consumeExports(quota, 50);
      final InMemoryExportJobStore jobs = InMemoryExportJobStore();

      final Response response = await _exportHandler(server, quota, jobs)(
        _post('/v1/export/epub', <String, Object?>{'project_id': projectId}),
      );

      expect(response.statusCode, 402);
      final Map<String, dynamic> error = await _error(response);
      expect(error['code'], 'plan_limit_reached');
      final Map<String, dynamic> details =
          error['details'] as Map<String, dynamic>;
      expect(details['feature'], 'exports');
      expect(details['limit'], 50);
      expect(details['used'], 50);
    });

    test(
      'incrémente le compteur une seule fois quand l\'export réussit',
      () async {
        final String projectId = await _seedProject(server);
        await _consumeExports(quota, 49);
        final InMemoryExportJobStore jobs = InMemoryExportJobStore();

        final Response response = await _exportHandler(server, quota, jobs)(
          _post('/v1/export/epub', <String, Object?>{'project_id': projectId}),
        );

        // La route cree le travail et repond aussitot : l'export n'est
        // pas fait dans la requete.
        expect(response.statusCode, 202);
        expect(
          await database.usageOf(
            userId: 'user-1',
            feature: QuotaFeature.exports,
            periodKey: '2026-10',
          ),
          49,
        );

        // Le worker produit le travail : le compteur n'est incremente
        // qu'une fois, et seulement au succes.
        await _worker(server, quota, jobs).drain();
        final int used = await database.usageOf(
          userId: 'user-1',
          feature: QuotaFeature.exports,
          periodKey: '2026-10',
        );
        expect(used, 50);
      },
    );
  });
}

/// La base des quotas sous test et la libération de ses ressources.
final class _QuotaFixture {
  /// Crée une fixture.
  const _QuotaFixture({required this.database, this.dispose});

  /// La base des quotas.
  final QuotaDatabase database;

  /// La libération des ressources, quand la base en a.
  final Future<void> Function()? dispose;
}

/// Le contrat des quotas, exécuté contre chaque implémentation de la base.
void _quotaContract(String name, Future<_QuotaFixture> Function() build) {
  group('quota — $name', () {
    late _QuotaFixture fixture;
    late QuotaService quota;
    late DateTime now;

    setUp(() async {
      fixture = await build();
      now = DateTime.utc(2026, 10, 26, 9);
      quota = QuotaService(database: fixture.database, clock: () => now);
    });

    tearDown(() async {
      await fixture.dispose?.call();
    });

    test('la formule gratuite refuse un deuxième projet', () async {
      await quota.ensureGauge(
        userId: 'user-1',
        feature: QuotaFeature.projects,
        current: 0,
      );

      await expectLater(
        quota.ensureGauge(
          userId: 'user-1',
          feature: QuotaFeature.projects,
          current: 1,
        ),
        throwsA(
          isA<PlanLimitException>()
              .having(
                (PlanLimitException error) => error.statusCode,
                'status',
                402,
              )
              .having(
                (PlanLimitException error) => error.code,
                'code',
                'plan_limit_reached',
              )
              .having(
                (PlanLimitException error) => error.details['feature'],
                'feature',
                'projects',
              )
              .having(
                (PlanLimitException error) => error.details['limit'],
                'limit',
                1,
              )
              .having(
                (PlanLimitException error) => error.details['used'],
                'used',
                1,
              ),
        ),
      );
    });

    test(
      'la formule Écrivain passe l\'export mais bloque au onzième projet',
      () async {
        await _assign(fixture.database, SubscriptionPlan.writer, now);

        await quota.ensureCounter(
          userId: 'user-1',
          feature: QuotaFeature.exports,
        );
        await quota.ensureGauge(
          userId: 'user-1',
          feature: QuotaFeature.projects,
          current: 9,
        );

        await expectLater(
          quota.ensureGauge(
            userId: 'user-1',
            feature: QuotaFeature.projects,
            current: 10,
          ),
          throwsA(isA<PlanLimitException>()),
        );
      },
    );

    test('le quota d\'IA est remis à zéro au changement de période', () async {
      await quota.recordConsumption(
        userId: 'user-1',
        feature: QuotaFeature.aiRewrites,
      );
      await quota.recordConsumption(
        userId: 'user-1',
        feature: QuotaFeature.aiRewrites,
      );

      await expectLater(
        quota.ensureCounter(userId: 'user-1', feature: QuotaFeature.aiRewrites),
        throwsA(isA<PlanLimitException>()),
      );

      now = DateTime.utc(2026, 10, 27, 9);

      await quota.ensureCounter(
        userId: 'user-1',
        feature: QuotaFeature.aiRewrites,
      );
      final QuotaSnapshot snapshot = await quota.snapshotOf('user-1');
      final QuotaCounter counter = snapshot.counters.firstWhere(
        (QuotaCounter item) => item.feature == QuotaFeature.aiRewrites,
      );
      expect(counter.used, 0);
    });

    test(
      'l\'essai de quatorze jours expire et la formule redevient gratuite',
      () async {
        await fixture.database.assignPlan(
          AccountPlan(
            userId: 'user-1',
            plan: SubscriptionPlan.writer,
            period: BillingPeriod.monthly,
            periodStartedAt: DateTime.utc(2026, 10, 1),
            trialEndsAt: DateTime.utc(2026, 10, 15),
          ),
        );

        now = DateTime.utc(2026, 10, 10);
        expect((await quota.planOf('user-1')).plan, SubscriptionPlan.writer);
        expect(await quota.statusOf('user-1'), PlanStatus.trial);

        now = DateTime.utc(2026, 10, 20);
        expect((await quota.planOf('user-1')).plan, SubscriptionPlan.free);
        expect(await quota.statusOf('user-1'), PlanStatus.free);

        await expectLater(
          quota.ensureGauge(
            userId: 'user-1',
            feature: QuotaFeature.projects,
            current: 1,
          ),
          throwsA(isA<PlanLimitException>()),
        );
      },
    );

    test('le compteur est incrémenté une seule fois quand l\'opération '
        'réussit', () async {
      await quota.recordConsumption(
        userId: 'user-1',
        feature: QuotaFeature.exports,
      );

      expect(
        await fixture.database.usageOf(
          userId: 'user-1',
          feature: QuotaFeature.exports,
          periodKey: '2026-10',
        ),
        1,
      );

      await _consumeExports(quota, 49);

      await expectLater(
        quota.ensureCounter(userId: 'user-1', feature: QuotaFeature.exports),
        throwsA(isA<PlanLimitException>()),
      );

      expect(
        await fixture.database.usageOf(
          userId: 'user-1',
          feature: QuotaFeature.exports,
          periodKey: '2026-10',
        ),
        50,
      );
    });

    test('une opération refusée ne consomme rien', () async {
      await _consumeExports(quota, 50);

      await expectLater(
        quota.ensureCounter(userId: 'user-1', feature: QuotaFeature.exports),
        throwsA(isA<PlanLimitException>()),
      );

      expect(
        await fixture.database.usageOf(
          userId: 'user-1',
          feature: QuotaFeature.exports,
          periodKey: '2026-10',
        ),
        50,
      );
    });

    test('le changement de formule respecte les règles de l\'essai', () async {
      final AccountPlan trial = await quota.changePlan(
        userId: 'user-1',
        plan: SubscriptionPlan.writer,
        period: BillingPeriod.monthly,
        startTrial: true,
      );

      expect(trial.plan, SubscriptionPlan.writer);
      expect(trial.trialEndsAt, DateTime.utc(2026, 11, 9, 9));

      await expectLater(
        quota.changePlan(
          userId: 'user-1',
          plan: SubscriptionPlan.pro,
          period: BillingPeriod.monthly,
          startTrial: true,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}

/// Affecte une formule payante au compte.
Future<void> _assign(
  QuotaDatabase database,
  SubscriptionPlan plan,
  DateTime now,
) {
  return database.assignPlan(
    AccountPlan(
      userId: 'user-1',
      plan: plan,
      period: BillingPeriod.monthly,
      periodStartedAt: now,
    ),
  );
}

/// Consomme [count] exports du compte.
Future<void> _consumeExports(QuotaService quota, int count) async {
  for (int index = 0; index < count; index++) {
    await quota.recordConsumption(
      userId: 'user-1',
      feature: QuotaFeature.exports,
    );
  }
}

/// Le gestionnaire qui transforme les erreurs en réponses.
Handler _handler(Router router) {
  final Logger logger = Logger(level: LogLevel.error, sink: (String line) {});
  return errorHandlerMiddleware(logger: logger)(router.call);
}

/// Le gestionnaire de la route d'export, câblé sur le garde-fou.
Handler _exportHandler(
  TestServer server,
  QuotaService quota,
  InMemoryExportJobStore jobs,
) {
  final Router router = Router();
  registerExportRoutes(
    router,
    server.dependencies,
    testConfig(),
    quota: quota,
    jobs: jobs,
  );
  return _handler(router);
}

/// Le worker qui produit les travaux de la file.
ExportWorker _worker(
  TestServer server,
  QuotaService quota,
  InMemoryExportJobStore jobs,
) {
  return ExportWorker(
    service: ExportService(
      jobs: jobs,
      projects: server.dependencies.projects,
      sync: server.dependencies.sync,
      storage: server.dependencies.storage,
      quota: quota,
    ),
  );
}

/// Crée un projet rempli et renvoie son identifiant.
Future<String> _seedProject(TestServer server) async {
  final Map<String, String> auth = <String, String>{
    'authorization': 'Bearer ${server.tokenFor('user-1')}',
  };
  final http.Response created = await server.post(
    '/v1/projects',
    headers: auth,
    body: <String, Object?>{'title': 'Manuscrit'},
  );
  final Map<String, dynamic> body =
      jsonDecode(created.body) as Map<String, dynamic>;
  final String projectId =
      (body['data'] as Map<String, dynamic>)['id'] as String;

  await server.post(
    '/v1/projects/$projectId/ops',
    headers: auth,
    body: <String, Object?>{
      'operations': <dynamic>[
        <String, Object?>{
          'op_id': 'op-1',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'user-1',
          'type': 'insertBlock',
          'payload': <String, Object?>{
            'block_id': 'block-1',
            'parent_id': null,
            'order_key': '5',
            'type': 'paragraph',
            'content': 'Il pleuvait sur la falaise.',
          },
          'schema_version': 1,
        },
      ],
    },
  );
  return projectId;
}

/// Le contexte d'authentification du compte de test.
Map<String, Object> _authContext() {
  return <String, Object>{
    authContextKey: const AuthContext(
      userId: 'user-1',
      email: 'user-1@example.test',
      claims: <String, dynamic>{},
    ),
  };
}

/// Une requête authentifiée.
Request _get(String path) {
  return Request(
    'GET',
    Uri.parse('http://localhost$path'),
    context: _authContext(),
  );
}

/// Une requête authentifiée portant un corps JSON.
Request _post(String path, Map<String, Object?> body) {
  return Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: <String, String>{'content-type': 'application/json'},
    body: jsonEncode(body),
    context: _authContext(),
  );
}

/// Le corps JSON décodé d'une réponse.
Future<Map<String, dynamic>> _body(Response response) async {
  final String raw = await response.readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// L'erreur JSON d'une réponse en échec.
Future<Map<String, dynamic>> _error(Response response) async {
  final Map<String, dynamic> body = await _body(response);
  return body['error'] as Map<String, dynamic>;
}
