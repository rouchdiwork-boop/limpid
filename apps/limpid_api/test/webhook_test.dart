import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  group('clés d\'API', () {
    late _Harness harness;

    setUp(() async {
      harness = await _Harness.start();
    });

    tearDown(() async {
      await harness.stop();
    });

    test('un compte hors Studio est refusé', () async {
      final http.Response response = await harness.post(
        '/v1/api-keys',
        <String, Object?>{'name': 'Intégration'},
        userId: 'user-free',
      );

      expect(response.statusCode, 403);
      expect(_errorOf(response)['code'], 'forbidden');
      expect(
        (_errorOf(response)['details']! as Map<String, dynamic>)['feature'],
        'api_and_webhooks',
      );
    });

    test(
      'la clé est montrée une fois, la base n\'en garde que l\'empreinte',
      () async {
        final http.Response created = await harness.post(
          '/v1/api-keys',
          <String, Object?>{
            'name': 'Intégration',
            'scopes': <String>['read'],
          },
          userId: 'user-studio',
        );

        expect(created.statusCode, 201);
        final Map<String, dynamic> data = _dataOf(created);
        final String secret = data['secret']! as String;
        expect(secret.startsWith('lk.'), isTrue);
        expect(data['scopes'], <String>['read']);

        // La base ne contient que l'empreinte de la clé.
        final List<Map<String, Object?>> rows = await harness.rowsOf(
          'SELECT * FROM api_keys',
        );
        expect(rows, hasLength(1));
        expect(rows.first['key_hash'], isNot(secret));
        expect(rows.first['key_hash'], hasLength(64));
        expect(rows.first.values.join(' '), isNot(contains(secret)));

        // La liste des clés ne montre jamais le secret.
        final http.Response listed = await harness.get(
          '/v1/api-keys',
          userId: 'user-studio',
        );
        expect(listed.statusCode, 200);
        final List<dynamic> items = _itemsOf(listed);
        expect(items, hasLength(1));
        expect(
          (items.first! as Map<String, dynamic>).containsKey('secret'),
          isFalse,
        );
      },
    );

    test(
      'la rotation garde l\'identité et l\'ancienne clé cesse de servir',
      () async {
        final String secret = await _createKey(harness);
        final String keyId = await _idOfKey(harness);

        final http.Response rotated = await harness.post(
          '/v1/api-keys/$keyId/rotate',
          <String, Object?>{},
          userId: 'user-studio',
        );
        expect(rotated.statusCode, 200);
        final Map<String, dynamic> data = _dataOf(rotated);
        expect(data['id'], keyId);
        final String fresh = data['secret']! as String;
        expect(fresh, isNot(secret));

        // L'ancienne clé ne sert plus.
        final http.Response withOld = await harness.get(
          '/v1/api/me',
          apiKey: secret,
        );
        expect(withOld.statusCode, 401);

        // La nouvelle clé sert.
        final http.Response withFresh = await harness.get(
          '/v1/api/me',
          apiKey: fresh,
        );
        expect(withFresh.statusCode, 200);
        expect(_dataOf(withFresh)['id'], keyId);
      },
    );

    test('une clé révoquée est refusée comme une clé inconnue', () async {
      final String secret = await _createKey(harness);
      final String keyId = await _idOfKey(harness);

      final http.Response revoked = await harness.delete(
        '/v1/api-keys/$keyId',
        userId: 'user-studio',
      );
      expect(revoked.statusCode, 200);

      final http.Response withRevoked = await harness.get(
        '/v1/api/me',
        apiKey: secret,
      );
      final http.Response withUnknown = await harness.get(
        '/v1/api/me',
        apiKey: 'lk.00000000000000000000000000.inconnu',
      );

      expect(withRevoked.statusCode, 401);
      expect(withUnknown.statusCode, 401);
      expect(_errorOf(withRevoked), _errorOf(withUnknown));
    });

    test('une clé absente ou inconnue est refusée clairement', () async {
      final http.Response missing = await harness.get('/v1/api/me');
      expect(missing.statusCode, 401);
      expect(
        (_errorOf(missing)['details']! as Map<String, dynamic>)['reason'],
        'missing_api_key',
      );

      final http.Response unknown = await harness.get(
        '/v1/api/me',
        apiKey: 'lk.00000000000000000000000000.inconnu',
      );
      expect(unknown.statusCode, 401);
      expect(
        (_errorOf(unknown)['details']! as Map<String, dynamic>)['reason'],
        'unknown_api_key',
      );
    });

    test('le périmètre borne les droits de la clé', () async {
      final http.Response created = await harness.post(
        '/v1/api-keys',
        <String, Object?>{
          'name': 'Écriture',
          'scopes': <String>['write'],
        },
        userId: 'user-studio',
      );
      final String secret = _dataOf(created)['secret']! as String;

      final http.Response response = await harness.get(
        '/v1/api/me',
        apiKey: secret,
      );
      expect(response.statusCode, 403);
      expect(
        (_errorOf(response)['details']! as Map<String, dynamic>)['scope'],
        'read',
      );
    });

    test(
      'les actions sensibles sont tracées dans le journal d\'audit',
      () async {
        await _createKey(harness);
        final String keyId = await _idOfKey(harness);
        await harness.post(
          '/v1/api-keys/$keyId/rotate',
          <String, Object?>{},
          userId: 'user-studio',
        );
        await harness.delete('/v1/api-keys/$keyId', userId: 'user-studio');

        final List<String> actions = harness.audit.entries
            .map((AuditEntry entry) => entry.action)
            .toList(growable: false);
        expect(actions, contains('api_key.created'));
        expect(actions, contains('api_key.rotated'));
        expect(actions, contains('api_key.revoked'));
      },
    );

    test('sans journal d\'audit, la création d\'une clé est refusée', () async {
      final _Harness bare = await _Harness.start(withAudit: false);
      addTearDown(bare.stop);

      final http.Response response = await bare.post(
        '/v1/api-keys',
        <String, Object?>{'name': 'Intégration'},
        userId: 'user-studio',
      );
      expect(response.statusCode, 503);
      expect(_errorOf(response)['code'], 'service_unavailable');
    });
  });

  group('webhooks sortants', () {
    late _Harness harness;
    late _Callback callback;

    setUp(() async {
      harness = await _Harness.start();
      callback = await _Callback.start();
    });

    tearDown(() async {
      await callback.stop();
      await harness.stop();
    });

    test('une URL de rappel doit être absolue', () async {
      final http.Response response = await harness.post(
        '/v1/webhooks/endpoints',
        <String, Object?>{
          'url': 'pas-une-url',
          'events': <String>['project.published'],
        },
        userId: 'user-studio',
      );

      expect(response.statusCode, 400);
      expect(_errorOf(response)['code'], 'validation_failed');
    });

    test('un événement inconnu est refusé', () async {
      final http.Response response = await harness.post(
        '/v1/webhooks/endpoints',
        <String, Object?>{
          'url': callback.url,
          'events': <String>['inexistant'],
        },
        userId: 'user-studio',
      );

      expect(response.statusCode, 400);
      expect(_errorOf(response)['code'], 'validation_failed');
    });

    test('la livraison est signée et journalisée', () async {
      final String secret = await _createEndpoint(harness, callback.url);

      final List<WebhookDeliveryRecord> deliveries = await harness.dispatcher
          .dispatch(
            userId: 'user-studio',
            event: WebhookEvent.projectPublished,
            data: <String, Object?>{'project_id': 'projet-1'},
          );

      expect(deliveries, hasLength(1));
      final WebhookDeliveryRecord delivery = deliveries.single;
      expect(delivery.status, WebhookDeliveryStatus.succeeded);
      expect(delivery.httpStatus, 200);
      expect(delivery.completedAt, isNotNull);
      expect(delivery.attempts, 1);

      // La charge reçue porte la signature HMAC du secret du point.
      expect(callback.received, hasLength(1));
      final _Received request = callback.received.single;
      expect(
        request.headers['x-limpid-signature'],
        'sha256=${_hmac(secret, request.body)}',
      );
      expect(request.headers['x-limpid-event'], 'project.published');
      expect(request.headers['x-limpid-delivery'], delivery.id);

      final Map<String, dynamic> payload =
          jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['type'], 'project.published');
      expect(payload['id'], delivery.id);

      // La livraison est lisible dans le journal du compte.
      final http.Response listed = await harness.get(
        '/v1/webhooks/deliveries',
        userId: 'user-studio',
      );
      expect(listed.statusCode, 200);
      final List<dynamic> items = _itemsOf(listed);
      expect(items, hasLength(1));
      final Map<String, dynamic> item = items.first! as Map<String, dynamic>;
      expect(item['status'], 'succeeded');
      expect(item['http_status'], 200);
      expect(item['completed_at'], isNotNull);
    });

    test('une livraison échouée est rejouable à la main', () async {
      final String secret = await _createEndpoint(
        harness,
        callback.url,
        event: 'export.completed',
      );
      callback.status = HttpStatus.internalServerError;

      final List<WebhookDeliveryRecord> deliveries = await harness.dispatcher
          .dispatch(
            userId: 'user-studio',
            event: WebhookEvent.exportCompleted,
            data: <String, Object?>{'export_id': 'export-1'},
          );
      final WebhookDeliveryRecord failed = deliveries.single;
      expect(failed.status, WebhookDeliveryStatus.failed);
      expect(failed.httpStatus, 500);

      callback.status = HttpStatus.ok;
      final http.Response replayed = await harness.post(
        '/v1/webhooks/deliveries/${failed.id}/replay',
        <String, Object?>{},
        userId: 'user-studio',
      );

      expect(replayed.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(replayed);
      expect(data['status'], 'succeeded');
      expect(data['attempts'], 2);
      // Le motif de l'échec a disparu : la livraison a abouti.
      expect(data['error_message'], isNull);

      // Le rejeu renvoie la même charge, vers l'URL déclarée.
      expect(callback.received, hasLength(2));
      expect(callback.received.last.body, callback.received.first.body);
      expect(
        callback.received.last.headers['x-limpid-signature'],
        'sha256=${_hmac(secret, callback.received.last.body)}',
      );
    });

    test('le rejeu ne part jamais vers une URL non déclarée', () async {
      await _createEndpoint(harness, callback.url, event: 'plan.changed');
      callback.status = HttpStatus.internalServerError;
      final List<WebhookDeliveryRecord> deliveries = await harness.dispatcher
          .dispatch(
            userId: 'user-studio',
            event: WebhookEvent.planChanged,
            data: <String, Object?>{'plan': 'studio'},
          );

      callback.status = HttpStatus.ok;
      final http.Response replayed = await harness.post(
        '/v1/webhooks/deliveries/${deliveries.single.id}/replay',
        <String, Object?>{'url': 'http://ailleurs.test/evasion'},
        userId: 'user-studio',
      );

      expect(replayed.statusCode, 200);
      expect(callback.received, hasLength(2));
      // La charge a bien été reçue par le point de rappel déclaré.
      expect(
        callback.received.last.headers['x-limpid-delivery'],
        deliveries.single.id,
      );
    });

    test('une livraison réussie ne se rejoue pas', () async {
      await _createEndpoint(harness, callback.url, event: 'quota.reached');
      final List<WebhookDeliveryRecord> deliveries = await harness.dispatcher
          .dispatch(
            userId: 'user-studio',
            event: WebhookEvent.quotaReached,
            data: <String, Object?>{'feature': 'exports'},
          );

      final http.Response replayed = await harness.post(
        '/v1/webhooks/deliveries/${deliveries.single.id}/replay',
        <String, Object?>{},
        userId: 'user-studio',
      );

      expect(replayed.statusCode, 409);
      expect(_errorOf(replayed)['code'], 'conflict');
    });

    test('la rotation du secret garde les deux signatures', () async {
      final String first = await _createEndpoint(harness, callback.url);

      final String endpointId = await _idOfEndpoint(harness);
      final http.Response rotated = await harness.post(
        '/v1/webhooks/endpoints/$endpointId/rotate-secret',
        <String, Object?>{},
        userId: 'user-studio',
      );
      expect(rotated.statusCode, 200);
      final String second = _dataOf(rotated)['secret']! as String;
      expect(second, isNot(first));

      await harness.dispatcher.dispatch(
        userId: 'user-studio',
        event: WebhookEvent.projectPublished,
        data: <String, Object?>{'project_id': 'projet-2'},
      );

      expect(callback.received, hasLength(1));
      final _Received request = callback.received.single;
      expect(
        request.headers['x-limpid-signature'],
        'sha256=${_hmac(second, request.body)}',
      );
      expect(
        request.headers['x-limpid-signature-previous'],
        'sha256=${_hmac(first, request.body)}',
      );
    });

    test(
      'un compte qui a quitté Studio ne reçoit plus ses livraisons',
      () async {
        await _createEndpoint(harness, callback.url);
        harness.plans['user-studio'] = 'free';

        final List<WebhookDeliveryRecord> deliveries = await harness.dispatcher
            .dispatch(
              userId: 'user-studio',
              event: WebhookEvent.projectPublished,
              data: <String, Object?>{'project_id': 'projet-3'},
            );

        expect(deliveries, isEmpty);
        expect(callback.received, isEmpty);
      },
    );

    test('le point de rappel et la livraison sont lisibles', () async {
      await _createEndpoint(harness, callback.url);

      final http.Response endpoints = await harness.get(
        '/v1/webhooks/endpoints',
        userId: 'user-studio',
      );
      expect(endpoints.statusCode, 200);
      final List<dynamic> items = _itemsOf(endpoints);
      expect(items, hasLength(1));
      final Map<String, dynamic> endpoint =
          items.first! as Map<String, dynamic>;
      expect(endpoint['url'], callback.url);
      expect(endpoint['events'], <String>['project.published']);
      expect(endpoint.containsKey('secret'), isFalse);
    });
  });

  group('port en mémoire', () {
    late InMemoryWebhookDatabase database;
    late ApiKeyService service;

    setUp(() {
      database = InMemoryWebhookDatabase();
      service = ApiKeyService(database: database);
    });

    test('la clé est créée, tournée puis révoquée', () async {
      final CreatedApiKey created = await service.create(
        userId: 'user-1',
        name: 'Intégration',
        scopes: <ApiKeyScope>{ApiKeyScope.read},
      );
      expect(created.secret.startsWith('lk.'), isTrue);
      expect(
        (await service.authenticate(created.secret))?.id,
        created.record.id,
      );

      // La rotation garde l'identité et invalide l'ancien secret.
      final CreatedApiKey rotated = await service.rotate(
        userId: 'user-1',
        keyId: created.record.id,
      );
      expect(rotated.record.id, created.record.id);
      expect(await service.authenticate(created.secret), isNull);
      expect(
        (await service.authenticate(rotated.secret))?.id,
        created.record.id,
      );

      // La révocation refuse la clé, comme une clé inconnue.
      await service.revoke(userId: 'user-1', keyId: created.record.id);
      expect(await service.authenticate(rotated.secret), isNull);
    });

    test('une clé d\'un autre compte est refusée', () async {
      final CreatedApiKey created = await service.create(
        userId: 'user-1',
        name: 'Intégration',
        scopes: <ApiKeyScope>{ApiKeyScope.read},
      );

      await expectLater(
        service.find(userId: 'user-2', keyId: created.record.id),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('la pagination suit le curseur', () async {
      for (int index = 0; index < 3; index++) {
        await service.create(
          userId: 'user-1',
          name: 'Clé $index',
          scopes: <ApiKeyScope>{ApiKeyScope.read},
        );
      }

      final WebhookPage<ApiKeyRecord> first = await service.list(
        userId: 'user-1',
        limit: 2,
      );
      expect(first.items, hasLength(2));
      expect(first.total, 3);
      expect(first.nextCursor, isNotNull);

      final WebhookPage<ApiKeyRecord> second = await service.list(
        userId: 'user-1',
        limit: 2,
        cursor: first.nextCursor,
      );
      expect(second.items, hasLength(1));
      expect(second.nextCursor, isNull);
    });
  });

  group('garde-fous de l\'URL de rappel', () {
    test('en production, http et les hôtes privés sont refusés', () async {
      final _Harness production = await _Harness.start(profile: 'prod');
      addTearDown(production.stop);

      final http.Response insecure = await production.post(
        '/v1/webhooks/endpoints',
        <String, Object?>{
          'url': 'http://exemple.test/rappel',
          'events': <String>['project.published'],
        },
        userId: 'user-studio',
      );
      expect(insecure.statusCode, 400);

      final http.Response private = await production.post(
        '/v1/webhooks/endpoints',
        <String, Object?>{
          'url': 'https://127.0.0.1/rappel',
          'events': <String>['project.published'],
        },
        userId: 'user-studio',
      );
      expect(private.statusCode, 400);

      final http.Response secure = await production.post(
        '/v1/webhooks/endpoints',
        <String, Object?>{
          'url': 'https://exemple.test/rappel',
          'events': <String>['project.published'],
        },
        userId: 'user-studio',
      );
      expect(secure.statusCode, 201);
    });

    test('la politique refuse les hôtes privés et les URL relatives', () {
      expect(
        () => validateCallbackUrl(
          'https://127.0.0.1/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl(
          'https://192.168.1.10/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl('https://[::1]/rappel', allowInsecure: false),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl(
          'https://interne.local/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl('/rappel', allowInsecure: false),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl(
          'https://utilisateur:motdepasse@exemple.test/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        validateCallbackUrl(
          'https://exemple.test/rappel',
          allowInsecure: false,
        ),
        'https://exemple.test/rappel',
      );
    });

    test('en développement, http et les hôtes locaux sont acceptés', () {
      expect(
        validateCallbackUrl(
          'http://127.0.0.1:8080/rappel',
          allowInsecure: true,
        ),
        'http://127.0.0.1:8080/rappel',
      );
    });
  });
}

/// La signature HMAC-SHA256 attendue dans l'en-tête de livraison.
String _hmac(String secret, String body) {
  return Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(body)).toString();
}

/// Crée une clé d'API et renvoie son secret.
Future<String> _createKey(_Harness harness) async {
  final http.Response response = await harness.post(
    '/v1/api-keys',
    <String, Object?>{
      'name': 'Intégration',
      'scopes': <String>['read'],
    },
    userId: 'user-studio',
  );
  expect(response.statusCode, 201);
  return _dataOf(response)['secret']! as String;
}

/// L'identifiant de la première clé du compte Studio.
Future<String> _idOfKey(_Harness harness) async {
  final http.Response response = await harness.get(
    '/v1/api-keys',
    userId: 'user-studio',
  );
  final List<dynamic> items = _itemsOf(response);
  return (items.first! as Map<String, dynamic>)['id']! as String;
}

/// Enregistre un point de rappel et renvoie son secret de signature.
///
/// Le point s'abonne par défaut au seul événement [event], pour que la
/// livraison de la suite vise bien le point de rappel.
Future<String> _createEndpoint(
  _Harness harness,
  String url, {
  String event = 'project.published',
}) async {
  final http.Response response = await harness.post(
    '/v1/webhooks/endpoints',
    <String, Object?>{
      'url': url,
      'events': <String>[event],
    },
    userId: 'user-studio',
  );
  expect(response.statusCode, 201);
  return _dataOf(response)['secret']! as String;
}

/// L'identifiant du premier point de rappel du compte Studio.
Future<String> _idOfEndpoint(_Harness harness) async {
  final http.Response response = await harness.get(
    '/v1/webhooks/endpoints',
    userId: 'user-studio',
  );
  final List<dynamic> items = _itemsOf(response);
  return (items.first! as Map<String, dynamic>)['id']! as String;
}

/// Les données d'une réponse réussie.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as Map<String, dynamic>;
}

/// Les éléments d'une réponse paginée.
List<dynamic> _itemsOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as List<dynamic>;
}

/// L'erreur d'une réponse en échec.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error']! as Map<String, dynamic>;
}

/// Une requête reçue par le point de rappel.
final class _Received {
  /// Crée une trace.
  const _Received(this.body, this.headers);

  /// Le corps reçu.
  final String body;

  /// Les en-têtes reçus.
  final Map<String, String> headers;
}

/// Le point de rappel de la suite de tests.
final class _Callback {
  _Callback(this._server, this.received);

  final HttpServer _server;
  final List<_Received> received;

  /// Le code répondu par le point de rappel.
  int status = HttpStatus.ok;

  /// L'URL du point de rappel.
  String get url => 'http://127.0.0.1:${_server.port}/rappel';

  /// Démarre le point de rappel.
  static Future<_Callback> start() async {
    final List<_Received> received = <_Received>[];
    late final _Callback callback;
    final HttpServer server = await shelf_io.serve(
      (Request request) async {
        final String body = await request.readAsString();
        received.add(
          _Received(body, Map<String, String>.from(request.headers)),
        );
        return Response(callback.status, body: 'ok');
      },
      InternetAddress.anyIPv4,
      0,
    );
    callback = _Callback(server, received);
    return callback;
  }

  /// Arrête le point de rappel.
  Future<void> stop() => _server.close(force: true);
}

/// L'API de la suite de tests, avec ses dépendances.
final class _Harness {
  _Harness({
    required this.server,
    required this.database,
    required this.issuer,
    required this.audit,
    required this.dispatcher,
    required this.plans,
  });

  final HttpServer server;
  final SqliteDatabase database;
  final TestTokenIssuer issuer;
  final InMemoryAuditLog audit;
  final WebhookDispatcher dispatcher;
  final Map<String, String?> plans;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  /// Démarre l'API de test.
  static Future<_Harness> start({
    String profile = 'dev',
    bool withAudit = true,
  }) async {
    final SqliteDatabase database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();

    final WebhookDatabase webhooks = SqliteWebhookDatabase(database);
    final InMemoryAuditLog audit = InMemoryAuditLog();
    final Map<String, String?> plans = <String, String?>{
      'user-studio': 'studio',
      'user-pro': 'pro',
      'user-free': 'free',
    };
    final WebhookDispatcher dispatcher = WebhookDispatcher(
      database: webhooks,
      guard: ApiAccessGuard(planOf: (String userId) async => plans[userId]),
      // Le rappel du test est sur la boucle locale : c'est le profil de
      // developpement, ou la politique d'hote prive est assouplie.
      allowPrivateHosts: true,
    );

    final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
    final TestTokenIssuer issuer = TestTokenIssuer(keyPair);
    final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
      issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
    });

    final AppConfig config = testConfig(
      overrides: <String, String>{
        'LIMPID_PROFILE': profile,
        'SUPABASE_SERVICE_ROLE_KEY': 'test-service-role-key',
      },
    );
    final Router router = Router();
    registerWebhookRoutes(
      router,
      webhooks,
      config,
      planOf: (String userId) async => plans[userId],
      audit: withAudit ? audit : null,
      dispatcher: dispatcher,
    );
    // L'API publique vit dans son propre fichier : elle est enregistrée à
    // côté des webhooks, sur les mêmes dépendances.
    registerPublicApiRoutes(
      router,
      config,
      projects: InMemoryProjectStore(),
      sync: InMemorySyncStore(),
      webhooks: webhooks,
      planOf: (String userId) async => plans[userId],
    );

    final Handler handler = const Pipeline()
        .addMiddleware(
          errorHandlerMiddleware(
            logger: Logger(level: LogLevel.warning),
            timeout: config.requestTimeout,
          ),
        )
        .addMiddleware(
          authenticationMiddleware(
            verifier: JwtVerifier(
              jwks: jwks,
              expectedIssuer: 'https://project.test/auth/v1',
            ),
            // Les routes de l'API publique s'authentifient par la clé
            // d'API : elles passent devant le jeton de session.
            exemptPrefixes: <String>[...publicPathPrefixes, '/v1/api/'],
          ),
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
      dispatcher: dispatcher,
      plans: plans,
    );
  }

  /// Les lignes brutes d'une table, pour vérifier ce que la base garde.
  Future<List<Map<String, Object?>>> rowsOf(String sql) async {
    return database.run(() {
      final ResultSet result = database.connection.select(sql);
      return result
          .map(
            (Row row) => <String, Object?>{
              for (final String column in row.keys) column: row[column],
            },
          )
          .toList(growable: false);
    });
  }

  /// Un GET authentifié par jeton ou par clé d'API.
  Future<http.Response> get(String path, {String? userId, String? apiKey}) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(userId, apiKey),
    );
  }

  /// Un POST authentifié par jeton ou par clé d'API.
  Future<http.Response> post(
    String path,
    Map<String, Object?> body, {
    String? userId,
    String? apiKey,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        ..._headers(userId, apiKey),
      },
      body: jsonEncode(body),
    );
  }

  /// Un DELETE authentifié par jeton ou par clé d'API.
  Future<http.Response> delete(String path, {String? userId, String? apiKey}) {
    return http.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(userId, apiKey),
    );
  }

  Map<String, String> _headers(String? userId, String? apiKey) {
    final Map<String, String> headers = <String, String>{};
    if (userId != null) {
      headers['authorization'] = 'Bearer ${issuer.issue(userId: userId)}';
    }
    if (apiKey != null) {
      headers[apiKeyHeader] = apiKey;
    }
    return headers;
  }

  /// Arrête l'API de test.
  Future<void> stop() async {
    await server.close(force: true);
    await database.close();
  }
}
