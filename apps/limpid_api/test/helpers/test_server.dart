import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';

import 'test_keys.dart';

/// An audit journal kept in memory, for the test suite.
final class InMemoryAuditLog implements AuditLog {
  /// The recorded entries.
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
    final List<AuditEntry> matching =
        entries
            .where(
              (AuditEntry entry) =>
                  entry.userId == userId &&
                  (action == null || entry.action == action),
            )
            .toList(growable: false)
          ..sort((AuditEntry left, AuditEntry right) {
            final int byDate = _momentOf(right).compareTo(_momentOf(left));
            if (byDate != 0) return byDate;
            return right.targetId.compareTo(left.targetId);
          });
    return matching.take(limit).toList(growable: false);
  }

  static DateTime _momentOf(AuditEntry entry) =>
      entry.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// A key set held in memory, for the test suite.
final class StaticJwksProvider implements JwksProvider {
  /// Creates a provider serving [entries].
  StaticJwksProvider(this.entries);

  /// The keys, indexed by identifier.
  final Map<String, JsonWebKey> entries;

  /// The number of refreshes.
  int refreshCount = 0;

  @override
  Future<Map<String, JsonWebKey>> keys() async => entries;

  @override
  Future<Map<String, JsonWebKey>> refresh() async {
    refreshCount += 1;
    return entries;
  }
}

/// An AI gateway returning canned answers, for the test suite.
final class StubAiGateway implements AiGateway {
  /// Creates a gateway.
  StubAiGateway({this.tokens = const <String>['Texte ', 'généré.']});

  /// The fragments returned by the gateway.
  final List<String> tokens;

  /// The number of free generations the gateway answered.
  int generateCalls = 0;

  /// The number of inline rewritings the gateway answered.
  int inlineCalls = 0;

  /// The number of questions the gateway answered.
  int queryCalls = 0;

  @override
  Stream<AiEvent> generate(AiGenerateRequest request) {
    generateCalls++;
    return _answer();
  }

  @override
  Stream<AiEvent> inline(AiInlineRequest request) {
    inlineCalls++;
    return _answer();
  }

  @override
  Stream<AiEvent> query(AiQueryRequest request) {
    queryCalls++;
    return _answer();
  }

  Stream<AiEvent> _answer() async* {
    final StringBuffer buffer = StringBuffer();
    for (final String token in tokens) {
      buffer.write(token);
      yield AiTokenEvent(token);
    }
    yield AiDoneEvent(
      text: buffer.toString(),
      inputTokens: 10,
      outputTokens: 5,
      estimatedCostUsd: 0.001,
    );
  }
}

/// The API running on an ephemeral port, with in-memory dependencies.
final class TestServer {
  TestServer._({
    required this.server,
    required this.dependencies,
    required this.issuer,
    required this.keyPair,
    required this.logLines,
  });

  /// The running server.
  final HttpServer server;

  /// The dependencies of the server.
  final AppDependencies dependencies;

  /// The issuer of the test tokens.
  final TestTokenIssuer issuer;

  /// The key pair signing the test tokens.
  final TestRsaKeyPair keyPair;

  /// The lines written by the logger.
  final List<String> logLines;

  /// The base URL of the server.
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// The store of the projects.
  InMemoryProjectStore get projects =>
      dependencies.projects as InMemoryProjectStore;

  /// The store of the sync journal.
  InMemorySyncStore get sync => dependencies.sync as InMemorySyncStore;

  /// The audit journal.
  InMemoryAuditLog get audit => dependencies.audit as InMemoryAuditLog;

  /// The payment gateway.
  StubPaymentGateway get payments =>
      dependencies.payments as StubPaymentGateway;

  /// The storage of the artefacts.
  ///
  /// The storage of the test suite holds in memory: a test that injects
  /// another storage reads [objectStorage] instead.
  InMemoryObjectStorage get storage =>
      dependencies.storage as InMemoryObjectStorage;

  /// The storage of the artefacts, whatever it is.
  ObjectStorage get objectStorage => dependencies.storage;

  /// The gateway of the model.
  StubAiGateway get ai => dependencies.ai as StubAiGateway;

  /// The key/value store.
  InMemoryKeyValueStore get keyValue =>
      dependencies.keyValue as InMemoryKeyValueStore;

  /// A valid token for [userId].
  String tokenFor(
    String userId, {
    Duration lifetime = const Duration(hours: 1),
  }) {
    return issuer.issue(
      userId: userId,
      expiresAt: DateTime.now().toUtc().add(lifetime),
    );
  }

  /// Gives [userId] the plan [plan].
  ///
  /// A test that creates several projects needs a plan that allows it: the
  /// free plan allows one.
  Future<void> givePlan(String userId, SubscriptionPlan plan) async {
    final InMemoryQuotaDatabase quotas =
        dependencies.quotas! as InMemoryQuotaDatabase;
    await quotas.assignPlan(
      AccountPlan(
        userId: userId,
        plan: plan,
        period: BillingPeriod.monthly,
        periodStartedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Active the second factor of [userId] and returns the proof to carry in
  /// the `x-limpid-2fa` header.
  ///
  /// The Pro and Studio plans require the double authentication (D-19): a
  /// test that gives such a plan to its account must also enable the second
  /// factor, otherwise the API refuses every call — which is the point.
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

  /// The `data` envelope of a response.
  static Map<String, dynamic> _dataOf(http.Response response) {
    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return payload['data'] as Map<String, dynamic>;
  }

  /// Performs a GET request.
  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.get(Uri.parse('$baseUrl$path'), headers: headers);
  }

  /// Performs a POST request.
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

  /// Performs a PUT request.
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

  /// Performs a PATCH request.
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

  /// Performs a DELETE request.
  Future<http.Response> delete(
    String path, {
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.delete(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Stops the server.
  Future<void> stop() async {
    await server.close(force: true);
  }
}

/// The configuration of the test server.
AppConfig testConfig({Map<String, String> overrides = const {}}) {
  return AppConfig.fromEnvironment(<String, String>{
    'PORT': '0',
    'DATABASE_URL': 'postgres://user:pass@localhost:5432/limpid',
    'SUPABASE_URL': 'https://project.test',
    'SUPABASE_ANON_KEY': 'test-anon-key',
    'REDIS_URL': 'redis://localhost:6379/0',
    'R2_ACCOUNT_ID': 'test-account',
    'R2_ACCESS_KEY_ID': 'test-access-key',
    'R2_SECRET_ACCESS_KEY': 'test-secret-key',
    'R2_BUCKET': 'test-bucket',
    'ANTHROPIC_API_KEY': 'test-anthropic-key',
    'STRIPE_SECRET_KEY': 'sk_test_key',
    'LOG_LEVEL': 'warning',
    'CORS_ALLOWED_ORIGINS': 'https://app.test',
    'AI_RATE_LIMIT_CAPACITY': '3',
    'AI_RATE_LIMIT_REFILL_PER_SECOND': '0.01',
    ...overrides,
  });
}

/// Starts the API on an ephemeral port, with in-memory dependencies.
///
/// [storage] replaces the in-memory storage: a test that measures le
/// stockage du compte peut y annoncer la taille de ses artefacts.
Future<TestServer> startTestServer({
  Map<String, String> configOverrides = const {},
  int keyBits = 2048,
  ObjectStorage? storage,
}) async {
  final TestRsaKeyPair keyPair = generateTestKeyPair(bits: keyBits);
  final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
  final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
    issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
  });

  final List<String> logLines = <String>[];
  final Logger logger = Logger(level: LogLevel.warning, sink: logLines.add);

  final InMemoryAuditLog audit = InMemoryAuditLog();
  final InMemoryQuotaDatabase quotas = InMemoryQuotaDatabase();
  final InMemoryProjectStore projects = InMemoryProjectStore();
  final InMemorySyncStore sync = InMemorySyncStore();
  final AppDependencies dependencies = AppDependencies(
    projects: projects,
    sync: sync,
    audit: audit,
    comments: InMemoryCommentStore(),
    purge: InMemoryAccountPurgeStore(entries: audit.entries),
    quotas: quotas,
    twoFactor: InMemoryTwoFactorDatabase(),
    teams: InMemoryTeamDatabase(
      planLookup: (String userId) async {
        final AccountPlan? plan = await quotas.planOf(userId);
        return plan?.plan.name;
      },
    ),
    admin: InMemoryAdminDatabase(),
    webhooks: InMemoryWebhookDatabase(),
    kdp: InMemoryKdpDatabase(
      planLookup: (String userId) async {
        final AccountPlan? plan = await quotas.planOf(userId);
        return plan?.plan.name;
      },
      projects: projects,
      sync: sync,
    ),
    kdpDeposits: InMemoryKdpDepositStore(),
    stripeEvents: InMemoryStripeEventDatabase(),
    // Le dépôt chez Amazon n'est pas configuré dans un test : le port le
    // dit, et la route répond 503 au lieu de prétendre que le livre est
    // arrivé.
    kdpGateway: const UnavailableKdpGateway(),
    ai: StubAiGateway(),
    payments: StubPaymentGateway(),
    storage: storage ?? InMemoryObjectStorage(),
    keyValue: InMemoryKeyValueStore(),
    jwtVerifier: JwtVerifier(
      jwks: jwks,
      expectedIssuer: 'https://project.test/auth/v1',
    ),
    logger: logger,
    databaseProbe: const AlwaysHealthyProbe(),
    syncHub: SyncHub(),
    shutdown: () async {},
  );

  final AppConfig config = testConfig(overrides: configOverrides);
  final HttpServer server = await createServer(
    config,
    dependencies: dependencies,
  );

  return TestServer._(
    server: server,
    dependencies: dependencies,
    issuer: issuer,
    keyPair: keyPair,
    logLines: logLines,
  );
}
