import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart';
import 'package:limpid_api/limpid_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  group('consentement à l\'IA', () {
    late _Harness harness;
    late Map<String, String> auth;

    setUp(() async {
      harness = await _Harness.start();
      auth = <String, String>{
        'authorization': 'Bearer ${harness.issuer.issue(userId: 'user-1')}',
      };
    });

    tearDown(() async {
      await harness.stop();
    });

    test('sans consentement, la génération est refusée en 403', () async {
      final http.Response response = await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.statusCode, 403);
      final Map<String, dynamic> error = _errorOf(response);
      expect(error['code'], 'ai_consent_required');
      expect(error['message'], contains('réglages'));
    });

    test('sans consentement, la fournisseur n\'est jamais appelée', () async {
      await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );
      await harness.post(
        '/v1/ai/inline',
        headers: auth,
        body: <String, Object?>{'action': 'expand', 'text': 'Un passage.'},
      );
      await harness.post(
        '/v1/ai/query',
        headers: auth,
        body: <String, Object?>{'question': 'Qui est le capitaine ?'},
      );

      expect(harness.provider.calls, 0);
    });

    test('le refus arrive avant l\'ouverture du flux', () async {
      final http.Response response = await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.statusCode, 403);
      expect(response.headers['content-type'], contains('application/json'));
      expect(response.headers['content-type'], isNot(contains('event-stream')));
      expect(response.body, isNot(contains('event:')));
    });

    test('le refus ne divulgue rien du compte', () async {
      final http.Response response = await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.body, isNot(contains('user-1')));
      expect(response.body, isNot(contains('falaise')));
    });

    test('avec le consentement, l\'appel part', () async {
      await harness.grant();

      final http.Response response = await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.statusCode, 200);
      expect(response.body, contains('event: done'));
      expect(harness.provider.calls, 1);
    });

    test('le retrait est effectif : plus aucun appel ne part', () async {
      await harness.grant();
      await harness.revoke();

      final http.Response response = await harness.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      expect(response.statusCode, 403);
      expect(harness.provider.calls, 0);
    });

    test(
      'le consentement est tracé, et la trace ne porte aucun texte',
      () async {
        await harness.grant();
        await harness.revoke();

        final List<AuditEntry> entries = harness.audit.entries;
        final AuditEntry granted = entries.firstWhere(
          (AuditEntry entry) => entry.action == 'ai.consent_granted',
        );
        final AuditEntry revoked = entries.firstWhere(
          (AuditEntry entry) => entry.action == 'ai.consent_revoked',
        );

        expect(granted.userId, 'user-1');
        expect(granted.targetType, 'ai_consent');
        expect(granted.targetId, 'anthropic');
        expect(granted.metadata['scope'], 'text_to_third_party');
        expect(granted.metadata['provider'], 'anthropic');
        expect(revoked.userId, 'user-1');
        expect(revoked.metadata['provider'], 'anthropic');

        // La trace dit qui a décidé et de quoi : elle ne porte ni le texte
        // de l'auteur, ni le texte de la demande.
        final String encoded = jsonEncode(
          entries.map((AuditEntry entry) => entry.toJson()).toList(),
        );
        expect(encoded, isNot(contains('falaise')));
        expect(encoded, isNot(contains('Décris')));
      },
    );

    test('un fournisseur local ne demande aucun accord', () async {
      final _Harness local = await _Harness.start(provider: 'ollama');
      addTearDown(local.stop);

      final http.Response response = await local.post(
        '/v1/ai/generate',
        headers: <String, String>{
          'authorization': 'Bearer ${local.issuer.issue(userId: 'user-1')}',
        },
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      // Le texte ne quitte pas la machine de l'auteur : aucun accord n'est
      // demande, et l'appel part.
      expect(response.statusCode, 200);
      expect(local.provider.calls, 1);
    });

    test('une passerelle sans service de consentement refuse tout', () async {
      final _Harness sansService = await _Harness.start(withConsents: false);
      addTearDown(sansService.stop);

      final http.Response response = await sansService.post(
        '/v1/ai/generate',
        headers: <String, String>{
          'authorization':
              'Bearer ${sansService.issuer.issue(userId: 'user-1')}',
        },
        body: <String, Object?>{'prompt': 'Décris la falaise.'},
      );

      // La garde est *fail-closed* : sans service, rien ne part.
      expect(response.statusCode, 503);
      expect(sansService.provider.calls, 0);
    });

    test('la lecture dit l\'état du consentement', () async {
      final http.Response before = await harness.get(
        '/v1/me/ai-consent',
        headers: auth,
      );
      expect(before.statusCode, 200);
      Map<String, dynamic> state = _dataOf(before);
      expect(state['is_granted'], isFalse);
      expect(state['requires_consent'], isTrue);
      expect(state['provider'], 'anthropic');
      expect(state['granted_at'], isNull);

      await harness.grant();

      final http.Response after = await harness.get(
        '/v1/me/ai-consent',
        headers: auth,
      );
      state = _dataOf(after);
      expect(state['is_granted'], isTrue);
      expect(state['granted_at'], isNotNull);
    });

    test('une route de consentement demande un compte', () async {
      final http.Response response = await harness.get('/v1/me/ai-consent');

      expect(response.statusCode, 401);
    });

    test('un compte ne lit pas le consentement d\'un autre', () async {
      await harness.grant();

      final http.Response response = await harness.get(
        '/v1/me/ai-consent',
        headers: <String, String>{
          'authorization': 'Bearer ${harness.issuer.issue(userId: 'user-2')}',
        },
      );

      expect(response.statusCode, 200);
      expect(_dataOf(response)['is_granted'], isFalse);
    });
  });
}

/// Une fournisseur qui compte ses appels, pour la suite.
///
/// La suite prouve ainsi que l'API n'a pas appelé le fournisseur quand elle
/// refuse une demande.
final class _CountingProvider implements LlmProvider {
  /// Le nombre d'appels reçus.
  int calls = 0;

  @override
  AiProviderKind get kind => AiProviderKind.anthropic;

  @override
  Future<AiResponse> complete(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async {
    calls += 1;
    return AiResponse(
      text: 'Texte généré.',
      usage: const AiUsage(inputTokens: 10, outputTokens: 5),
      model: 'test',
      provider: AiProviderKind.anthropic,
    );
  }

  @override
  Stream<AiChunk> stream(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async* {
    calls += 1;
    yield const AiChunk(text: 'Texte ');
    yield const AiChunk(text: 'généré.');
    yield const AiChunk.done(usage: AiUsage(inputTokens: 10, outputTokens: 5));
  }
}

/// Le serveur de test du consentement.
///
/// Le serveur porte la **vraie** passerelle de production, branchée sur une
/// fournisseur qui compte ses appels : la suite prouve donc que la garde
/// refuse avant l'appel, et pas après.
final class _Harness {
  _Harness({
    required this.server,
    required this.database,
    required this.issuer,
    required this.audit,
    required this.provider,
    required this.consents,
  });

  final HttpServer server;
  final SqliteDatabase database;
  final TestTokenIssuer issuer;
  final InMemoryAuditLog audit;
  final _CountingProvider provider;
  final AiConsentService consents;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Démarre le serveur de test.
  ///
  /// [provider] est le fournisseur que la passerelle interroge vraiment,
  /// et [withConsents] dit si le service du consentement est câblé.
  static Future<_Harness> start({
    String provider = 'anthropic',
    bool withConsents = true,
  }) async {
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
    final _CountingProvider counting = _CountingProvider();
    final AiConsentService consents = AiConsentService(
      store: SqliteAiConsentStore(database),
    );

    final AppDependencies dependencies = AppDependencies(
      projects: InMemoryProjectStore(),
      sync: InMemorySyncStore(),
      audit: audit,
      comments: InMemoryCommentStore(),
      purge: InMemoryAccountPurgeStore(entries: audit.entries),
      ai: LimpidAiGateway(
        client: AiClient.withProviders(<AiProviderKind, LlmProvider>{
          AiProviderKind.anthropic: counting,
        }),
        consents: withConsents ? consents : null,
        provider: provider,
      ),
      payments: StubPaymentGateway(),
      storage: InMemoryObjectStorage(),
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

    final AppConfig config = testConfig();
    final Router router = Router();
    registerAiRoutes(router, dependencies, config);
    registerAiConsentRoutes(router, dependencies, config, consents: consents);

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
      InternetAddress.anyIPv4,
      0,
    );
    return _Harness(
      server: server,
      database: database,
      issuer: issuer,
      audit: audit,
      provider: counting,
      consents: consents,
    );
  }

  /// Donne le consentement du compte `user-1`.
  Future<void> grant() async {
    final http.Response response = await post(
      '/v1/me/ai-consent',
      headers: _authOf('user-1'),
    );
    expect(response.statusCode, 200);
  }

  /// Retire le consentement du compte `user-1`.
  Future<void> revoke() async {
    final http.Response response = await delete(
      '/v1/me/ai-consent',
      headers: _authOf('user-1'),
    );
    expect(response.statusCode, 200);
  }

  Map<String, String> _authOf(String userId) {
    return <String, String>{
      'authorization': 'Bearer ${issuer.issue(userId: userId)}',
    };
  }

  /// Un GET authentifié.
  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.get(Uri.parse('$baseUrl$path'), headers: headers);
  }

  /// Un POST authentifié.
  Future<http.Response> post(
    String path, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Un DELETE authentifié.
  Future<http.Response> delete(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.delete(Uri.parse('$baseUrl$path'), headers: headers);
  }

  /// Arrête le serveur et ferme la base.
  Future<void> stop() async {
    await server.close(force: true);
    await database.close();
  }
}

/// Les données d'une réponse réussie.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as Map<String, dynamic>;
}

/// L'erreur d'une réponse en échec.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error']! as Map<String, dynamic>;
}
