import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/services/ai_token_budget.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  late _AiServer server;

  setUp(() async {
    server = await _AiServer.start();
    await server.givePlan('user-1', SubscriptionPlan.writer);
    await server.givePlan('user-2', SubscriptionPlan.writer);
  });

  tearDown(() async {
    await server.stop();
  });

  group('garde par requête', () {
    test(
      'un appel sous le budget aboutit et ses jetons sont comptés',
      () async {
        final http.Response response = await server.generate(
          'user-1',
          'Décris la falaise.',
        );

        expect(response.statusCode, 200);
        expect(server.gateway.calls, 1);
        expect(
          await server.tokensUsed('user-1'),
          _CountingAiGateway.reportedTokens,
        );
        expect(_doneOf(response)['tokens_estimated'], isFalse);
      },
    );

    test('un appel trop gros est refusé et le fournisseur n\'est jamais '
        'appelé', () async {
      final http.Response response = await server.generate(
        'user-1',
        _textOfLength(100000),
      );

      expect(response.statusCode, 429);
      final Map<String, dynamic> error = _error(response);
      expect(error['code'], 'quota_exceeded');
      final Map<String, dynamic> details =
          error['details'] as Map<String, dynamic>;
      expect(details['feature'], 'ai_generate');
      expect(details['scope'], 'request');
      expect(details['limit'], maxAiTokensPerRequest);
      expect(server.gateway.calls, 0);
      expect(await server.tokensUsed('user-1'), 0);
    });

    test(
      'une réécriture trop grosse est refusée avant le fournisseur',
      () async {
        final http.Response response = await server.inline(
          'user-1',
          'expand',
          _textOfLength(100000),
        );

        expect(response.statusCode, 429);
        expect(_error(response)['code'], 'quota_exceeded');
        expect(server.gateway.calls, 0);
        expect(await server.tokensUsed('user-1'), 0);
      },
    );

    test(
      'une demande d\'une longue génération dépasse le budget d\'un appel',
      () async {
        final http.Response response = await server.generate(
          'user-1',
          'Écris le chapitre.',
          maxTokens: 32000,
        );

        expect(response.statusCode, 429);
        expect(_error(response)['code'], 'quota_exceeded');
        expect(server.gateway.calls, 0);
      },
    );

    test('une demande avec un plafond de sortie ordinaire passe', () async {
      final http.Response response = await server.generate(
        'user-1',
        'Décris la falaise.',
        maxTokens: 4000,
      );

      expect(response.statusCode, 200);
      expect(server.gateway.calls, 1);
    });
  });

  group('garde par période', () {
    test('le quota mensuel atteint refuse l\'appel suivant', () async {
      await server.consumeTokens('user-1', 500000);

      final http.Response response = await server.generate(
        'user-1',
        'Décris la falaise.',
      );

      expect(response.statusCode, 429);
      final Map<String, dynamic> error = _error(response);
      expect(error['code'], 'quota_exceeded');
      final Map<String, dynamic> details =
          error['details'] as Map<String, dynamic>;
      expect(details['feature'], 'ai_tokens');
      expect(details['scope'], 'period');
      expect(details['limit'], 500000);
      expect(details['used'], 500000);
      expect(details['period'], 'month');
      expect(server.gateway.calls, 0);
    });

    test('la réponse porte la date de la remise à zéro', () async {
      await server.consumeTokens('user-1', 500000);

      final http.Response response = await server.generate(
        'user-1',
        'Décris la falaise.',
      );

      final Map<String, dynamic> details =
          _error(response)['details'] as Map<String, dynamic>;
      final DateTime reset = DateTime.parse(details['reset_at'] as String);
      expect(reset.isUtc, isTrue);
      expect(reset.day, 1);
      expect(reset.hour, 0);
      expect(reset.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('un appel refusé ne consomme rien', () async {
      await server.consumeTokens('user-1', 500000);

      await server.generate('user-1', 'Décris la falaise.');

      expect(await server.tokensUsed('user-1'), 500000);
    });

    test('les comptes ne mélangent pas leurs compteurs', () async {
      await server.generate('user-1', 'Décris la falaise.');
      await server.consumeTokens('user-2', 500000);

      expect(
        await server.tokensUsed('user-1'),
        _CountingAiGateway.reportedTokens,
      );
      expect(await server.tokensUsed('user-2'), 500000);

      final http.Response refused = await server.generate(
        'user-2',
        'Décris la falaise.',
      );
      expect(refused.statusCode, 429);

      final http.Response allowed = await server.generate(
        'user-1',
        'Encore la falaise.',
      );
      expect(allowed.statusCode, 200);
      expect(server.gateway.calls, 2);
    });

    test('la formule gratuite ne borne pas les jetons', () async {
      await server.givePlan('user-3', SubscriptionPlan.free);

      final http.Response response = await server.generate(
        'user-3',
        'Décris la falaise.',
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> counter = await server.counterOf('user-3');
      expect(counter['limit'], isNull);
      expect(counter['used'], _CountingAiGateway.reportedTokens);
    });
  });

  group('compte des jetons', () {
    test(
      'le compteur de jetons paraît dans l\'instantané des quotas',
      () async {
        await server.generate('user-1', 'Décris la falaise.');

        final Map<String, dynamic> counter = await server.counterOf('user-1');

        expect(counter['feature'], 'ai_tokens');
        expect(counter['kind'], 'counter');
        expect(counter['limit'], 500000);
        expect(counter['used'], _CountingAiGateway.reportedTokens);
        expect(counter['period'], 'month');
      },
    );

    test(
      'le catalogue public annonce le quota de jetons de la formule',
      () async {
        final http.Response response = await server.get(
          '/v1/plans',
          userId: 'user-1',
        );

        expect(response.statusCode, 200);
        final List<dynamic> plans = _data(response) as List<dynamic>;
        final Map<String, dynamic> writer = plans
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (Map<String, dynamic> plan) => plan['plan'] == 'writer',
            );
        final Map<String, dynamic> free = plans
            .cast<Map<String, dynamic>>()
            .firstWhere((Map<String, dynamic> plan) => plan['plan'] == 'free');
        expect((writer['quota'] as Map<String, dynamic>)['ai_tokens'], 500000);
        // La formule gratuite ne vend pas de jetons : elle n'en borne pas.
        expect((free['quota'] as Map<String, dynamic>)['ai_tokens'], isNull);
      },
    );

    test(
      'un compte que la passeuse ne déclare pas est une estimation',
      () async {
        const AiDoneEvent event = AiDoneEvent(
          text: 'Texte',
          inputTokens: 10,
          outputTokens: 5,
          estimatedCostUsd: 0.001,
        );

        expect(event.isTokenCountEstimated, isTrue);
      },
    );

    test('un compte estimé est marqué comme tel et reste compté', () async {
      server.gateway.isTokenCountEstimated = true;

      final http.Response response = await server.generate(
        'user-1',
        'Décris la falaise.',
      );

      expect(_doneOf(response)['tokens_estimated'], isTrue);
      expect(
        await server.tokensUsed('user-1'),
        _CountingAiGateway.reportedTokens,
      );
    });
  });
}

/// Une passerelle IA qui compte ses appels et rapporte sa consommation.
///
/// Elle ne joint aucun fournisseur : elle répond un texte écrit d'avance,
/// comme le ferait une passeuse de test.
final class _CountingAiGateway implements AiGateway {
  /// Crée une passeuse.
  _CountingAiGateway();

  /// Le nombre de tokens que la passeuse rapporte.
  static const int reportedTokens = 120 + 45;

  /// Le nombre d'appels reçus.
  int calls = 0;

  /// Le nombre de tokens d'entrée que la passeuse rapporte.
  final int inputTokens = 120;

  /// Le nombre de tokens de sortie que la passeuse rapporte.
  final int outputTokens = 45;

  /// La nature du compte que la passeuse rapporte.
  bool isTokenCountEstimated = false;

  @override
  Future<void> ensureConsent({required String userId}) async {}

  @override
  Stream<AiEvent> generate(AiGenerateRequest request) {
    calls += 1;
    return _answer();
  }

  @override
  Stream<AiEvent> inline(AiInlineRequest request) {
    calls += 1;
    return _answer();
  }

  @override
  Stream<AiEvent> query(AiQueryRequest request) {
    calls += 1;
    return _answer();
  }

  Stream<AiEvent> _answer() async* {
    yield const AiTokenEvent('Texte ');
    yield const AiTokenEvent('généré.');
    yield AiDoneEvent(
      text: 'Texte généré.',
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCostUsd: 0.001,
      isTokenCountEstimated: isTokenCountEstimated,
    );
  }
}

/// Le serveur de test de la garde des jetons.
///
/// La passeuse IA y compte ses appels : la suite prouve ainsi que l'API
/// n'a pas appelé le fournisseur quand elle refuse une demande.
final class _AiServer {
  _AiServer._({
    required this.server,
    required this.gateway,
    required this.quotas,
    required this.issuer,
  });

  /// Le serveur en écoute.
  final HttpServer server;

  /// La passeuse IA qui compte les appels.
  final _CountingAiGateway gateway;

  /// La base des quotas.
  final InMemoryQuotaDatabase quotas;

  /// L'émetteur des jetons de session.
  final TestTokenIssuer issuer;

  /// L'adresse du serveur.
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Démarre un serveur dont la passeuse IA compte ses appels.
  static Future<_AiServer> start({
    Map<String, String> configOverrides = const <String, String>{},
  }) async {
    final Map<String, String> overrides = <String, String>{
      // La suite fait plusieurs appels par compte : le seau de débit ne
      // doit pas mordre avant les gardes de jetons.
      'AI_RATE_LIMIT_CAPACITY': '200',
      ...configOverrides,
    };
    final TestServer base = await startTestServer(configOverrides: overrides);
    final _CountingAiGateway gateway = _CountingAiGateway();
    final AppDependencies dependencies = _withGateway(
      base.dependencies,
      gateway,
    );
    final HttpServer server = await createServer(
      testConfig(overrides: overrides),
      dependencies: dependencies,
    );
    await base.stop();
    return _AiServer._(
      server: server,
      gateway: gateway,
      quotas: base.dependencies.quotas! as InMemoryQuotaDatabase,
      issuer: base.issuer,
    );
  }

  /// Donne au compte [userId] la formule [plan].
  Future<void> givePlan(String userId, SubscriptionPlan plan) {
    return quotas.assignPlan(
      AccountPlan(
        userId: userId,
        plan: plan,
        period: BillingPeriod.monthly,
        periodStartedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// La consommation de jetons du compte, dans la période courante.
  Future<int> tokensUsed(String userId) {
    return quotas.usageOf(
      userId: userId,
      feature: QuotaFeature.aiTokens,
      periodKey: QuotaPeriod.month.keyAt(DateTime.now().toUtc()),
    );
  }

  /// Le compteur de jetons du compte, dans l'instantané des quotas.
  Future<Map<String, dynamic>> counterOf(String userId) async {
    final http.Response response = await get('/v1/me/quota', userId: userId);
    expect(response.statusCode, 200);
    final Map<String, dynamic> data = _data(response) as Map<String, dynamic>;
    final List<dynamic> quotas = data['quotas'] as List<dynamic>;
    return quotas.cast<Map<String, dynamic>>().firstWhere(
      (Map<String, dynamic> item) => item['feature'] == 'ai_tokens',
    );
  }

  /// Consomme [tokens] jetons au compte [userId].
  Future<void> consumeTokens(String userId, int tokens) {
    return quotas.consume(
      userId: userId,
      feature: QuotaFeature.aiTokens,
      periodKey: QuotaPeriod.month.keyAt(DateTime.now().toUtc()),
      amount: tokens,
    );
  }

  /// Demande une génération à l'IA.
  Future<http.Response> generate(
    String userId,
    String prompt, {
    int? maxTokens,
  }) {
    return post(
      '/v1/ai/generate',
      userId: userId,
      body: <String, Object?>{'prompt': prompt, 'max_tokens': ?maxTokens},
    );
  }

  /// Demande une réécriture à l'IA.
  Future<http.Response> inline(String userId, String action, String text) {
    return post(
      '/v1/ai/inline',
      userId: userId,
      body: <String, Object?>{'action': action, 'text': text},
    );
  }

  /// Effectue une lecture.
  Future<http.Response> get(String path, {required String userId}) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'authorization': 'Bearer ${tokenFor(userId)}'},
    );
  }

  /// Effectue une écriture.
  Future<http.Response> post(
    String path, {
    required String userId,
    Object? body,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer ${tokenFor(userId)}',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Un jeton de session valide pour [userId].
  String tokenFor(String userId) {
    return issuer.issue(
      userId: userId,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  /// Arrête le serveur.
  Future<void> stop() => server.close(force: true);
}

/// Les mêmes dépendances, avec une autre passeuse IA.
///
/// La passeuse est la seule chose qui change : le reste — la base des
/// quotas, les projets, le journal — vient du serveur de test partagé.
AppDependencies _withGateway(AppDependencies base, AiGateway gateway) {
  return AppDependencies(
    projects: base.projects,
    sync: base.sync,
    audit: base.audit,
    comments: base.comments,
    purge: base.purge,
    ai: gateway,
    payments: base.payments,
    storage: base.storage,
    keyValue: base.keyValue,
    jwtVerifier: base.jwtVerifier,
    logger: base.logger,
    databaseProbe: base.databaseProbe,
    syncHub: base.syncHub,
    shutdown: base.shutdown,
    quotas: base.quotas,
    twoFactor: base.twoFactor,
  );
}

/// Un texte de [length] caractères.
String _textOfLength(int length) => List<String>.filled(length, 'a').join();

/// L'enveloppe `data` d'une réponse.
Object? _data(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data'];
}

/// L'erreur d'une réponse en échec.
Map<String, dynamic> _error(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error'] as Map<String, dynamic>;
}

/// Le corps de l'événement `done` d'une réponse en flux.
Map<String, dynamic> _doneOf(http.Response response) {
  for (final String line in response.body.split('\n')) {
    if (!line.startsWith('data: ')) continue;
    final Object? decoded = jsonDecode(line.substring('data: '.length));
    if (decoded is Map<String, dynamic> &&
        decoded.containsKey('tokens_estimated')) {
      return decoded;
    }
  }
  fail('La réponse ne porte pas d\'événement done.');
}
