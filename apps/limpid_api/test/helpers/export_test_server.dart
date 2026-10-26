import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/routes/export_routes.dart';
import 'package:limpid_api/src/routes/project_routes.dart';
import 'package:limpid_api/src/routes/sync_routes.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'test_keys.dart';
import 'test_server.dart';

/// Le serveur de test de l'export.
///
/// Le serveur expose les routes de l'export, la file des travaux et le
/// worker qui les produit. Un test demande un export, fait tourner le
/// worker, puis lit l'artefact : c'est le chemin que suit un vrai serveur,
/// où l'export ne se fait pas dans la requête.
///
/// Le serveur ne sert que les routes dont l'export a besoin : les livres,
/// leur synchronisation, le second facteur et la publication Amazon.
final class ExportTestServer {
  ExportTestServer._({
    required this.server,
    required this.dependencies,
    required this.issuer,
    required this.jobs,
    required this.quota,
    required this.logger,
    required this.clock,
  });

  /// Le serveur qui répond.
  final HttpServer server;

  /// Les dépendances du serveur.
  final AppDependencies dependencies;

  /// L'issuer des jetons de session.
  final TestTokenIssuer issuer;

  /// La file des travaux.
  final InMemoryExportJobStore jobs;

  /// Le garde-fou des quotas du serveur.
  final QuotaService quota;

  /// Le journal du serveur.
  final Logger logger;

  /// L'horloge du serveur, `null` quand elle est celle du système.
  ///
  /// Une horloge injectée fait passer le temps sans attendre : c'est elle
  /// qui mesure l'expiration de l'artefact.
  final DateTime Function()? clock;

  /// L'adresse du serveur.
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Le stockage des artefacts.
  InMemoryObjectStorage get storage =>
      dependencies.storage as InMemoryObjectStorage;

  /// Le journal d'audit.
  InMemoryAuditLog get audit => dependencies.audit as InMemoryAuditLog;

  /// La base des formules et des compteurs.
  InMemoryQuotaDatabase get quotas =>
      dependencies.quotas! as InMemoryQuotaDatabase;

  /// Les livres des comptes.
  InMemoryProjectStore get projects =>
      dependencies.projects as InMemoryProjectStore;

  /// Le service d'export, avec le quota [quota] quand il est donné.
  ///
  /// Le quota du serveur est celui des dépendances ; un test qui mesure
  /// une autre base de quotas handing le sien.
  ExportService serviceWith({QuotaService? quota}) {
    return ExportService(
      jobs: jobs,
      projects: dependencies.projects,
      sync: dependencies.sync,
      storage: dependencies.storage,
      kdp: dependencies.kdp,
      quota: quota ?? this.quota,
      audit: dependencies.audit,
      dispatcher: dependencies.webhookDispatcher,
      logger: logger,
      clock: clock,
    );
  }

  /// Le worker qui produit les travaux, avec le quota [quota] quand il est
  /// donné.
  ExportWorker workerWith({QuotaService? quota}) =>
      ExportWorker(service: serviceWith(quota: quota));

  /// Fait tourner le worker : la file est vidée.
  Future<int> runWorker({QuotaService? quota}) =>
      workerWith(quota: quota).drain();

  /// Le travail [jobId], `null` quand il n'existe pas.
  Future<ExportJobRecord?> job(String jobId) => jobs.findById(jobId);

  /// Un jeton valide pour [userId].
  String tokenFor(
    String userId, {
    Duration lifetime = const Duration(hours: 1),
  }) {
    return issuer.issue(
      userId: userId,
      expiresAt: DateTime.now().toUtc().add(lifetime),
    );
  }

  /// Donne [userId] la formule [plan].
  Future<void> givePlan(String userId, SubscriptionPlan plan) async {
    await quotas.assignPlan(
      AccountPlan(
        userId: userId,
        plan: plan,
        period: BillingPeriod.monthly,
        periodStartedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Active le second facteur de [userId] et rend la preuve à porter.
  Future<String> enableTwoFactor(String userId) async {
    final Map<String, String> headers = <String, String>{
      'authorization': 'Bearer ${tokenFor(userId)}',
    };
    final http.Response enrolled = await post(
      '/v1/me/2fa/enroll',
      headers: headers,
      body: <String, Object?>{},
    );
    final String secret = _dataOf(enrolled)['secret']! as String;
    final String code = totpCode(secret, DateTime.now().toUtc());
    await post(
      '/v1/me/2fa/confirm',
      headers: headers,
      body: <String, Object?>{'code': code},
    );
    final http.Response verified = await post(
      '/v1/me/2fa/verify',
      headers: headers,
      body: <String, Object?>{'code': code},
    );
    return _dataOf(verified)['proof']! as String;
  }

  /// Le `data` de l'enveloppe d'une réponse.
  static Map<String, dynamic> _dataOf(http.Response response) {
    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return payload['data'] as Map<String, dynamic>;
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

  /// Effectue une requête PATCH.
  Future<http.Response> patch(
    String path, {
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.patch(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Arrête le serveur.
  Future<void> stop() async {
    await server.close(force: true);
  }

  /// Démarre le serveur de test de l'export.
  ///
  /// [storage] remplace le stockage en mémoire : un test qui mesure le
  /// stockage du compte y annonce la taille de ses artefacts.
  static Future<ExportTestServer> start({
    ObjectStorage? storage,
    int keyBits = 2048,
    Map<String, String> configOverrides = const {},
    DateTime Function()? clock,
  }) async {
    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: keyBits);
    final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });
    final Logger logger = Logger(level: LogLevel.warning);

    final AppDependencies dependencies = buildTestDependencies(
      jwks: jwks,
      logger: logger,
      storage: storage,
    );
    final InMemoryExportJobStore jobs = InMemoryExportJobStore();
    final QuotaService quota = QuotaService(
      database: dependencies.quotas!,
      dispatcher: dependencies.webhookDispatcher,
    );

    final AppConfig config = testConfig(overrides: configOverrides);
    final Router router = Router();
    registerProjectRoutes(router, dependencies, config, quota: quota);
    registerSyncRoutes(router, dependencies, config, quota: quota);
    registerExportRoutes(
      router,
      dependencies,
      config,
      quota: quota,
      jobs: jobs,
      clock: clock,
    );
    registerTwoFactorRoutes(
      router,
      dependencies.twoFactor!,
      config,
      planOf: dependencies.planOf,
    );
    if (dependencies.kdp != null) {
      registerKdpRoutes(router, dependencies.kdp!, config);
      if (dependencies.kdpDeposits != null && dependencies.kdpGateway != null) {
        registerKdpPublishingRoutes(
          router,
          KdpPublishingService(
            publications: dependencies.kdp!,
            deposits: dependencies.kdpDeposits!,
            gateway: dependencies.kdpGateway!,
          ),
          config,
        );
      }
    }

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: logger,
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(
          authenticationMiddleware(
            verifier: dependencies.jwtVerifier,
            twoFactorGuard: dependencies.twoFactorGuard,
          ),
        )
        .addHandler(router.call);

    final HttpServer server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      0,
    );

    return ExportTestServer._(
      server: server,
      dependencies: dependencies,
      issuer: issuer,
      jobs: jobs,
      quota: quota,
      logger: logger,
      clock: clock,
    );
  }
}
