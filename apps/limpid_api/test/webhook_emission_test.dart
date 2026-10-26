import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_api/src/routes/ai_routes.dart';
import 'package:limpid_api/src/routes/export_routes.dart';
import 'package:limpid_api/src/routes/project_routes.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

/// La phrase que le manuscrit porte et que la charge ne doit pas transporter.
const String secretSentence = 'Un passage que personne ne doit lire.';

/// L'URL du point de rappel simulé.
const String callbackUrl = 'https://rappel.test/hook';

void main() {
  group('les webhooks sortants sont émis', () {
    late _Harness harness;

    setUp(() async {
      harness = await _Harness.start();
      await harness.givePlan('user-1', SubscriptionPlan.studio);
    });

    tearDown(() async {
      await harness.stop();
    });

    test(
      'publier un livre déclenche une livraison project.published',
      () async {
        await harness.createEndpoint('user-1', <String>['project.published']);
        final String projectId = await harness.createProject(
          'user-1',
          'Le titre',
        );

        final http.Response response = await harness.patch(
          '/v1/projects/$projectId',
          <String, Object?>{'is_public': true},
          userId: 'user-1',
        );
        expect(response.statusCode, 200);

        final _Sent sent = await harness.awaitDelivery('project.published');
        expect(sent.payload['type'], 'project.published');
        final Map<String, dynamic> data =
            sent.payload['data'] as Map<String, dynamic>;
        expect(data['project_id'], projectId);
        expect(data['title'], 'Le titre');
      },
    );

    test(
      'un export terminé déclenche une livraison export.completed',
      () async {
        await harness.createEndpoint('user-1', <String>['export.completed']);
        final String projectId = await harness.createProject(
          'user-1',
          'Le titre',
        );
        await harness.appendContent(projectId, 'user-1');

        final http.Response response = await harness.post(
          '/v1/export/md',
          <String, Object?>{'project_id': projectId},
          userId: 'user-1',
        );
        expect(response.statusCode, 200);

        final _Sent sent = await harness.awaitDelivery('export.completed');
        expect(sent.payload['type'], 'export.completed');
        final Map<String, dynamic> data =
            sent.payload['data'] as Map<String, dynamic>;
        expect(data['project_id'], projectId);
        expect(data['format'], 'markdown');
      },
    );

    test(
      'un changement de formule déclenche une livraison plan.changed',
      () async {
        await harness.createEndpoint('user-1', <String>['plan.changed']);

        final http.Response response = await harness.post(
          '/v1/me/plan',
          <String, Object?>{
            'plan': 'writer',
            'period': 'monthly',
            'start_trial': true,
          },
          userId: 'user-1',
        );
        expect(response.statusCode, 200);

        final _Sent sent = await harness.awaitDelivery('plan.changed');
        expect(sent.payload['type'], 'plan.changed');
        final Map<String, dynamic> data =
            sent.payload['data'] as Map<String, dynamic>;
        expect(data['plan'], 'writer');
        expect(data['previous_plan'], 'studio');
        expect(data['period'], 'monthly');
      },
    );

    test('une invitation d\'équipe déclenche une livraison '
        'team.invitation_sent', () async {
      await harness.createEndpoint('user-1', <String>['team.invitation_sent']);
      final String teamId = await harness.createTeam('user-1', 'LesClefs');

      final http.Response response = await harness.post(
        '/v1/teams/$teamId/invitations',
        <String, Object?>{'user_id': 'user-2', 'role': 'betaReader'},
        userId: 'user-1',
      );
      expect(response.statusCode, 201);

      final _Sent sent = await harness.awaitDelivery('team.invitation_sent');
      expect(sent.payload['type'], 'team.invitation_sent');
      final Map<String, dynamic> data =
          sent.payload['data'] as Map<String, dynamic>;
      expect(data['team_id'], teamId);
      expect(data['role'], 'betaReader');
      // L'invitation ne divulgue pas l'identifiant du compte invité.
      expect(sent.body, isNot(contains('user-2')));
    });

    test('une jauge atteinte déclenche une livraison quota.reached', () async {
      await harness.createEndpoint('user-1', <String>['quota.reached']);
      // La formule Studio accorde mille réécritures par jour : le compte
      // les a toutes consommées.
      await harness.consumeRewrites('user-1', 1000);

      final http.Response response = await harness.post(
        '/v1/ai/generate',
        <String, Object?>{'prompt': 'Un texte'},
        userId: 'user-1',
      );
      expect(response.statusCode, 402);

      final _Sent sent = await harness.awaitDelivery('quota.reached');
      expect(sent.payload['type'], 'quota.reached');
      final Map<String, dynamic> data =
          sent.payload['data'] as Map<String, dynamic>;
      expect(data['feature'], 'ai_rewrites');
      expect(data['limit'], 1000);
      expect(data['used'], 1000);
    });

    test('un point de rappel qui ne s\'abonne pas à l\'événement ne reçoit '
        'rien', () async {
      await harness.createEndpoint('user-1', <String>['plan.changed']);
      final String projectId = await harness.createProject(
        'user-1',
        'Le titre',
      );
      await harness.patch('/v1/projects/$projectId', <String, Object?>{
        'is_public': true,
      }, userId: 'user-1');

      // Le contrôle prouve que la chaîne de livraison est vivante : le
      // changement de formule, lui, est abonné.
      await harness.post('/v1/me/plan', <String, Object?>{
        'plan': 'writer',
        'period': 'monthly',
        'start_trial': true,
      }, userId: 'user-1');
      await harness.awaitDelivery('plan.changed');

      expect(harness.deliveredEvents, <String>['plan.changed']);
    });

    test('un point de rappel inactif ne reçoit rien', () async {
      final _Endpoint endpoint = await harness.createEndpoint(
        'user-1',
        <String>['project.published'],
      );
      await harness.disableEndpoint(endpoint.id);
      final String projectId = await harness.createProject(
        'user-1',
        'Le titre',
      );
      await harness.patch('/v1/projects/$projectId', <String, Object?>{
        'is_public': true,
      }, userId: 'user-1');

      // Le contrôle : le compte change de formule, un point abonné reçoit.
      await harness.createEndpoint('user-1', <String>['plan.changed']);
      await harness.post('/v1/me/plan', <String, Object?>{
        'plan': 'writer',
        'period': 'monthly',
        'start_trial': true,
      }, userId: 'user-1');
      await harness.awaitDelivery('plan.changed');

      expect(harness.deliveredEvents, <String>['plan.changed']);
    });

    test(
      'un rappel mort ne fait pas échouer l\'export qui l\'a déclenché',
      () async {
        await harness.createEndpoint('user-1', <String>['export.completed']);
        harness.callback.status = HttpStatus.internalServerError;
        final String projectId = await harness.createProject(
          'user-1',
          'Le titre',
        );
        await harness.appendContent(projectId, 'user-1');

        final http.Response response = await harness.post(
          '/v1/export/md',
          <String, Object?>{'project_id': projectId},
          userId: 'user-1',
        );

        // L'export a réussi : le rappel est mort, le livre est là.
        expect(response.statusCode, 200);
        expect(response.bodyBytes, isNotEmpty);

        await harness.awaitDelivery('export.completed');
        final WebhookPage<WebhookDeliveryRecord> deliveries = await harness
            .webhooks
            .listDeliveries(userId: 'user-1', limit: 10);
        expect(deliveries.items, hasLength(1));
        expect(deliveries.items.single.status, WebhookDeliveryStatus.failed);
      },
    );

    test('la charge utile ne porte ni secret ni texte du livre', () async {
      final _Endpoint endpoint = await harness.createEndpoint(
        'user-1',
        <String>['export.completed'],
      );
      final String projectId = await harness.createProject(
        'user-1',
        'Le titre',
      );
      await harness.appendContent(projectId, 'user-1');

      await harness.post('/v1/export/md', <String, Object?>{
        'project_id': projectId,
      }, userId: 'user-1');
      final _Sent sent = await harness.awaitDelivery('export.completed');

      expect(sent.body, isNot(contains(endpoint.secret)));
      expect(sent.body, isNot(contains(secretSentence)));
    });

    test(
      'la charge utile de la publication ne porte pas le texte du livre',
      () async {
        final _Endpoint endpoint = await harness.createEndpoint(
          'user-1',
          <String>['project.published'],
        );
        final String projectId = await harness.createProject(
          'user-1',
          'Le titre',
        );
        await harness.appendContent(projectId, 'user-1');

        await harness.patch('/v1/projects/$projectId', <String, Object?>{
          'is_public': true,
        }, userId: 'user-1');
        final _Sent sent = await harness.awaitDelivery('project.published');

        expect(sent.body, isNot(contains(endpoint.secret)));
        expect(sent.body, isNot(contains(secretSentence)));
        // Le titre du livre, lui, fait partie de l'événement.
        expect(sent.body, contains('Le titre'));
      },
    );

    test('deux comptes ne se déclenchent pas l\'un l\'autre', () async {
      await harness.givePlan('user-2', SubscriptionPlan.studio);
      await harness.createEndpoint('user-1', <String>['project.published']);

      // Le compte de l'autre publie : ses livres ne déclenchent rien.
      final String otherId = await harness.createProject('user-2', 'Chez nous');
      await harness.patch('/v1/projects/$otherId', <String, Object?>{
        'is_public': true,
      }, userId: 'user-2');

      // Le contrôle : le compte inscrit publie, son point de rappel reçoit.
      final String ownId = await harness.createProject('user-1', 'Le titre');
      await harness.patch('/v1/projects/$ownId', <String, Object?>{
        'is_public': true,
      }, userId: 'user-1');
      final _Sent sent = await harness.awaitDelivery('project.published');

      final Map<String, dynamic> data =
          sent.payload['data'] as Map<String, dynamic>;
      expect(data['project_id'], ownId);
      expect(sent.body, isNot(contains('Chez nous')));
    });

    test('la publication est tracée dans le journal d\'audit', () async {
      final String projectId = await harness.createProject(
        'user-1',
        'Le titre',
      );
      await harness.patch('/v1/projects/$projectId', <String, Object?>{
        'is_public': true,
      }, userId: 'user-1');

      final List<String> actions = harness.audit.entries
          .map((AuditEntry entry) => entry.action)
          .toList(growable: false);
      expect(actions, contains('project.published'));
    });

    test(
      'l\'invitation d\'équipe est tracée dans le journal d\'audit',
      () async {
        final String teamId = await harness.createTeam('user-1', 'LesClefs');
        await harness.post('/v1/teams/$teamId/invitations', <String, Object?>{
          'user_id': 'user-2',
          'role': 'betaReader',
        }, userId: 'user-1');

        final List<String> actions = harness.audit.entries
            .map((AuditEntry entry) => entry.action)
            .toList(growable: false);
        expect(actions, contains('team.invitation_sent'));
      },
    );
  });

  group('la charge utile est nettoyée', () {
    test('les champs secrets et le texte du livre sont retirés', () {
      final Map<String, Object?> data = <String, Object?>{
        'project_id': 'projet-1',
        'title': 'Le titre',
        'secret': 'un-secret',
        'api_key': 'une-cle',
        'refresh_token': 'un-jeton',
        'content': 'Le texte du livre',
        'text': 'Le texte du livre',
        'body': 'Le corps',
      };

      final Map<String, Object?> safe = sanitizeWebhookData(data);

      expect(safe.keys, <String>['project_id', 'title']);
    });

    test('les champs ordinaires traversent le nettoyage', () {
      final Map<String, Object?> data = <String, Object?>{
        'project_id': 'projet-1',
        'format': 'markdown',
        'bytes': 1024,
        'limit': 10,
        'used': 10,
      };

      expect(sanitizeWebhookData(data), data);
    });

    test('un secret caché dans une carte imbriquée est retiré', () {
      final Map<String, Object?> data = <String, Object?>{
        'project_id': 'projet-1',
        'meta': <String, Object?>{
          'title': 'Le titre',
          'api_key': 'une-cle',
          'content': 'Le texte du livre',
        },
      };

      final Map<String, Object?> safe = sanitizeWebhookData(data);

      final Map<String, Object?> meta = safe['meta']! as Map<String, Object?>;
      expect(meta.keys, <String>['title']);
    });

    test('une liste imbriquée est nettoyée aussi', () {
      final Map<String, Object?> data = <String, Object?>{
        'projects': <Object?>[
          <String, Object?>{'id': 'projet-1', 'token': 'un-jeton'},
        ],
      };

      final Map<String, Object?> safe = sanitizeWebhookData(data);

      final List<Object?> projects = safe['projects']! as List<Object?>;
      final Map<String, Object?> first =
          projects.single! as Map<String, Object?>;
      expect(first.keys, <String>['id']);
    });
  });
}

/// Une requête reçue par le point de rappel simulé.
final class _Sent {
  /// Crée une trace.
  _Sent(this.body, this.headers);

  /// Le corps reçu.
  final String body;

  /// Les en-têtes reçus.
  final Map<String, String> headers;

  /// La charge décodée.
  Map<String, dynamic> get payload => jsonDecode(body) as Map<String, dynamic>;

  /// Le nom technique de l'événement livré.
  String get event => payload['type']! as String;
}

/// Un point de rappel enregistré : son identifiant et son secret.
final class _Endpoint {
  /// Crée un point de rappel.
  _Endpoint({required this.id, required this.secret});

  /// L'identifiant du point de rappel.
  final String id;

  /// Le secret de signature du point de rappel.
  final String secret;
}

/// Le point de rappel simulé : il reçoit les livraisons et les compte.
final class _Callback {
  /// Les requêtes reçues.
  final List<_Sent> received = <_Sent>[];

  /// Le code répondu au point de rappel.
  int status = HttpStatus.ok;

  /// Répond à la requête [request].
  Future<http.Response> handle(http.Request request) async {
    received.add(
      _Sent(request.body, Map<String, String>.from(request.headers)),
    );
    return http.Response('ok', status);
  }
}

/// L'API de la suite de tests, avec ses dépendances.
final class _Harness {
  _Harness({
    required this.server,
    required this.issuer,
    required this.dispatcher,
    required this.webhooks,
    required this.quotas,
    required this.projects,
    required this.sync,
    required this.teams,
    required this.audit,
    required this.callback,
  });

  /// Le serveur qui répond.
  final HttpServer server;

  /// L'issuer des jetons de session.
  final TestTokenIssuer issuer;

  /// Le dispatcher des webhooks.
  final WebhookDispatcher dispatcher;

  /// La base des points de rappel et des livraisons.
  final InMemoryWebhookDatabase webhooks;

  /// La base des formules et des compteurs.
  final InMemoryQuotaDatabase quotas;

  /// La base des projets.
  final InMemoryProjectStore projects;

  /// Le journal de synchronisation.
  final InMemorySyncStore sync;

  /// La base des équipes.
  final InMemoryTeamDatabase teams;

  /// Le journal d'audit.
  final InMemoryAuditLog audit;

  /// Le point de rappel simulé.
  final _Callback callback;

  /// L'adresse du serveur.
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Les événements livrés, dans l'ordre d'arrivée.
  List<String> get deliveredEvents =>
      callback.received.map((_Sent sent) => sent.event).toList(growable: false);

  /// Démarre l'API de test.
  static Future<_Harness> start() async {
    final _Callback callback = _Callback();
    final InMemoryWebhookDatabase webhooks = InMemoryWebhookDatabase();
    final InMemoryQuotaDatabase quotas = InMemoryQuotaDatabase();
    final InMemoryProjectStore projects = InMemoryProjectStore();
    final InMemorySyncStore sync = InMemorySyncStore();
    final InMemoryAuditLog audit = InMemoryAuditLog();
    final InMemoryTeamDatabase teams = InMemoryTeamDatabase(
      planLookup: (String userId) async {
        final AccountPlan? plan = await quotas.planOf(userId);
        return plan?.plan.name;
      },
    );
    final WebhookDispatcher dispatcher = WebhookDispatcher(
      database: webhooks,
      client: MockClient(callback.handle),
      // Le rappel du test est sur la boucle locale : c'est le profil de
      // developpement, ou la politique d'hote prive est assouplie.
      allowPrivateHosts: true,
    );

    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
    final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });
    final JwtVerifier verifier = JwtVerifier(
      jwks: jwks,
      expectedIssuer: 'https://project.test/auth/v1',
    );

    final AppDependencies dependencies = AppDependencies(
      projects: projects,
      sync: sync,
      audit: audit,
      comments: InMemoryCommentStore(),
      purge: InMemoryAccountPurgeStore(entries: audit.entries),
      quotas: quotas,
      teams: teams,
      admin: InMemoryAdminDatabase(),
      webhooks: webhooks,
      stripeEvents: InMemoryStripeEventDatabase(),
      ai: StubAiGateway(),
      payments: StubPaymentGateway(),
      storage: InMemoryObjectStorage(),
      keyValue: InMemoryKeyValueStore(),
      jwtVerifier: verifier,
      logger: Logger(level: LogLevel.warning),
      databaseProbe: const AlwaysHealthyProbe(),
      syncHub: SyncHub(),
      shutdown: () async {},
      webhookDispatcher: dispatcher,
    );

    final QuotaService quota = QuotaService(
      database: quotas,
      dispatcher: dispatcher,
    );

    final AppConfig config = testConfig();
    final Router router = Router();
    registerProjectRoutes(router, dependencies, config, quota: quota);
    registerExportRoutes(router, dependencies, config, quota: quota);
    registerAiRoutes(router, dependencies, config, quota: quota);
    registerTeamRoutes(
      router,
      teams,
      config,
      audit: audit,
      dispatcher: dispatcher,
    );
    registerQuotaRoutes(
      router,
      quotas,
      config,
      audit: audit,
      dispatcher: dispatcher,
    );
    registerWebhookRoutes(
      router,
      webhooks,
      config,
      planOf: (String userId) async {
        final AccountPlan? plan = await quotas.planOf(userId);
        return plan?.plan.name;
      },
      audit: audit,
      dispatcher: dispatcher,
    );

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning),
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(authenticationMiddleware(verifier: verifier))
        .addHandler(router.call);

    final HttpServer server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      0,
    );
    return _Harness(
      server: server,
      issuer: issuer,
      dispatcher: dispatcher,
      webhooks: webhooks,
      quotas: quotas,
      projects: projects,
      sync: sync,
      teams: teams,
      audit: audit,
      callback: callback,
    );
  }

  /// Donne la formule [plan] au compte [userId].
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

  /// Consomme [amount] réécritures pour le compte [userId].
  Future<void> consumeRewrites(String userId, int amount) async {
    await quotas.consume(
      userId: userId,
      feature: QuotaFeature.aiRewrites,
      periodKey: QuotaPeriod.day.keyAt(DateTime.now().toUtc()),
      amount: amount,
    );
  }

  /// Enregistre un point de rappel et rend son identifiant et son secret.
  Future<_Endpoint> createEndpoint(String userId, List<String> events) async {
    final http.Response response = await post(
      '/v1/webhooks/endpoints',
      <String, Object?>{'url': callbackUrl, 'events': events},
      userId: userId,
    );
    expect(response.statusCode, 201);
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
    return _Endpoint(
      id: data['id']! as String,
      secret: data['secret']! as String,
    );
  }

  /// Désactive le point de rappel [endpointId].
  Future<void> disableEndpoint(String endpointId) async {
    final WebhookEndpointRecord? endpoint = await webhooks.findEndpoint(
      endpointId,
    );
    expect(endpoint, isNotNull);
    await webhooks.updateEndpoint(endpoint!.copyWith(isActive: false));
  }

  /// Crée un projet pour le compte [userId] et rend son identifiant.
  Future<String> createProject(String userId, String title) async {
    final http.Response response = await post('/v1/projects', <String, Object?>{
      'title': title,
    }, userId: userId);
    expect(response.statusCode, 201);
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>)['id']! as String;
  }

  /// Crée une équipe pour le compte [userId] et rend son identifiant.
  Future<String> createTeam(String userId, String name) async {
    final http.Response response = await post('/v1/teams', <String, Object?>{
      'name': name,
    }, userId: userId);
    expect(response.statusCode, 201);
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>)['id']! as String;
  }

  /// Ajoute un chapitre au projet [projectId].
  Future<void> appendContent(
    String projectId,
    String userId, [
    String sentence = secretSentence,
  ]) async {
    final DateTime now = DateTime.now().toUtc();
    await sync.append(
      projectId: projectId,
      operations: <SyncOpRecord>[
        SyncOpRecord(
          opId: 'op-1',
          projectId: projectId,
          docId: 'doc-1',
          lamport: 1,
          authorId: userId,
          type: 'insertBlock',
          payload: <String, dynamic>{
            'block_id': 'block-1',
            'parent_id': null,
            'order_key': '5',
            'type': 'heading1',
            'content': 'Chapitre premier',
          },
          schemaVersion: 1,
          createdAt: now,
        ),
        SyncOpRecord(
          opId: 'op-2',
          projectId: projectId,
          docId: 'doc-1',
          lamport: 2,
          authorId: userId,
          type: 'insertBlock',
          payload: <String, dynamic>{
            'block_id': 'block-2',
            'parent_id': 'block-1',
            'order_key': '7',
            'type': 'paragraph',
            'content': sentence,
          },
          schemaVersion: 1,
          createdAt: now,
        ),
      ],
    );
  }

  /// Attend la livraison de l'événement [event] et la rend.
  Future<_Sent> awaitDelivery(String event) async {
    for (int attempt = 0; attempt < 300; attempt++) {
      for (final _Sent sent in callback.received) {
        if (sent.event == event) return sent;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('La livraison de $event n\'est jamais arrivée.');
  }

  /// Un GET authentifié par jeton.
  Future<http.Response> get(String path, {required String userId}) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{'authorization': 'Bearer ${_token(userId)}'},
    );
  }

  /// Un POST authentifié par jeton.
  Future<http.Response> post(
    String path,
    Map<String, Object?> body, {
    required String userId,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer ${_token(userId)}',
      },
      body: jsonEncode(body),
    );
  }

  /// Un PATCH authentifié par jeton.
  Future<http.Response> patch(
    String path,
    Map<String, Object?> body, {
    required String userId,
  }) {
    return http.patch(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer ${_token(userId)}',
      },
      body: jsonEncode(body),
    );
  }

  String _token(String userId) => issuer.issue(userId: userId);

  /// Arrête l'API de test.
  Future<void> stop() async {
    await server.close(force: true);
  }
}
