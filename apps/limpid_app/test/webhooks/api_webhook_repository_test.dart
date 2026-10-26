import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_webhook_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';

void main() {
  group('ApiWebhookRepository', () {
    test('lit les clés du compte', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/api-keys');
        return _ok(<Object?>[
          <String, Object?>{
            'id': 'key-1',
            'name': 'Intégration',
            'scopes': <String>['read', 'write'],
            'is_active': true,
            'is_revoked': false,
            'created_at': '2026-01-15T10:00:00.000Z',
            'rotated_at': null,
            'revoked_at': null,
            'last_used_at': '2026-01-20T08:30:00.000Z',
          },
        ]);
      });

      final List<ApiKey> keys = await repository.apiKeys();

      expect(keys, hasLength(1));
      expect(keys.first.id, 'key-1');
      expect(keys.first.name, 'Intégration');
      expect(keys.first.scopes, <ApiKeyScope>{
        ApiKeyScope.read,
        ApiKeyScope.write,
      });
      expect(keys.first.isUsable, isTrue);
      expect(keys.first.createdAt, DateTime.utc(2026, 1, 15, 10));
      expect(keys.first.lastUsedAt, DateTime.utc(2026, 1, 20, 8, 30));
    });

    test('crée une clé et rend son secret', () async {
      Map<String, Object?>? body;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/api-keys');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _created(<String, Object?>{
          'id': 'key-2',
          'name': 'Intégration',
          'scopes': <String>['read'],
          'is_active': true,
          'is_revoked': false,
          'created_at': '2026-02-01T10:00:00.000Z',
          'secret': 'lk.key-2.s3cr3t',
        });
      });

      final CreatedApiKey created = await repository.createApiKey(
        name: 'Intégration',
        scopes: <ApiKeyScope>{ApiKeyScope.read},
      );

      expect(body?['name'], 'Intégration');
      expect(body?['scopes'], <String>['read']);
      expect(created.secret, 'lk.key-2.s3cr3t');
      expect(created.key.id, 'key-2');
    });

    test('renouvelle le secret d’une clé', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/api-keys/key-1/rotate');
        return _ok(<String, Object?>{
          'id': 'key-1',
          'name': 'Intégration',
          'scopes': <String>['read'],
          'is_active': true,
          'is_revoked': false,
          'created_at': '2026-01-15T10:00:00.000Z',
          'secret': 'lk.key-1.nouveau',
        });
      });

      final CreatedApiKey rotated = await repository.rotateApiKey('key-1');

      expect(rotated.secret, 'lk.key-1.nouveau');
    });

    test('supprime une clé', () async {
      String? method;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        method = request.method;
        expect(request.url.path, '/v1/api-keys/key-1');
        return _ok(<String, Object?>{'id': 'key-1', 'is_revoked': true});
      });

      await repository.deleteApiKey('key-1');

      expect(method, 'DELETE');
    });

    test('lit les points de réception', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/webhooks/endpoints');
        return _ok(<Object?>[
          <String, Object?>{
            'id': 'endpoint-1',
            'url': 'https://exemple.test/limpid',
            'events': <String>['project.published', 'export.completed'],
            'is_active': true,
            'has_previous_secret': true,
            'previous_secret_expires_at': '2026-02-02T10:00:00.000Z',
            'created_at': '2026-01-15T10:00:00.000Z',
            'updated_at': '2026-01-16T10:00:00.000Z',
          },
        ]);
      });

      final List<WebhookEndpoint> endpoints = await repository.endpoints();

      expect(endpoints, hasLength(1));
      expect(endpoints.first.url, 'https://exemple.test/limpid');
      expect(endpoints.first.events, <String>{
        'project.published',
        'export.completed',
      });
      expect(endpoints.first.hasPreviousSecret, isTrue);
      expect(
        endpoints.first.previousSecretExpiresAt,
        DateTime.utc(2026, 2, 2, 10),
      );
    });

    test('crée un point de réception et rend son secret', () async {
      Map<String, Object?>? body;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/webhooks/endpoints');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _created(<String, Object?>{
          'id': 'endpoint-2',
          'url': 'https://exemple.test/limpid',
          'events': <String>['project.published'],
          'is_active': true,
          'has_previous_secret': false,
          'created_at': '2026-02-01T10:00:00.000Z',
          'updated_at': '2026-02-01T10:00:00.000Z',
          'secret': 'whsec_secret',
        });
      });

      final WebhookEndpointSecret created = await repository.createEndpoint(
        url: 'https://exemple.test/limpid',
        events: <String>{'project.published'},
      );

      expect(body?['url'], 'https://exemple.test/limpid');
      expect(body?['events'], <String>['project.published']);
      expect(created.secret, 'whsec_secret');
      expect(created.endpoint.id, 'endpoint-2');
    });

    test('modifie un point de réception', () async {
      Map<String, Object?>? body;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/webhooks/endpoints/endpoint-1');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'id': 'endpoint-1',
          'url': 'https://exemple.test/limpid',
          'events': <String>['export.completed'],
          'is_active': true,
          'has_previous_secret': false,
          'created_at': '2026-01-15T10:00:00.000Z',
          'updated_at': '2026-02-01T10:00:00.000Z',
        });
      });

      final WebhookEndpoint updated = await repository.updateEndpoint(
        'endpoint-1',
        url: 'https://exemple.test/limpid',
        events: <String>{'export.completed'},
      );

      expect(body?['url'], 'https://exemple.test/limpid');
      expect(body?['events'], <String>['export.completed']);
      expect(updated.events, <String>{'export.completed'});
    });

    test('ne renvoie pas les champs absents d’une modification', () async {
      Map<String, Object?>? body;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'id': 'endpoint-1',
          'url': 'https://exemple.test/limpid',
          'events': <String>['export.completed'],
          'is_active': true,
          'has_previous_secret': false,
          'created_at': '2026-01-15T10:00:00.000Z',
          'updated_at': '2026-02-01T10:00:00.000Z',
        });
      });

      await repository.updateEndpoint('endpoint-1');

      expect(body, isEmpty);
    });

    test('renouvelle le secret de signature', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/v1/webhooks/endpoints/endpoint-1/rotate-secret',
        );
        return _ok(<String, Object?>{
          'id': 'endpoint-1',
          'url': 'https://exemple.test/limpid',
          'events': <String>['project.published'],
          'is_active': true,
          'has_previous_secret': true,
          'created_at': '2026-01-15T10:00:00.000Z',
          'updated_at': '2026-02-01T10:00:00.000Z',
          'secret': 'whsec_nouveau',
        });
      });

      final WebhookEndpointSecret rotated = await repository
          .rotateEndpointSecret('endpoint-1');

      expect(rotated.secret, 'whsec_nouveau');
    });

    test('supprime un point de réception', () async {
      String? method;
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        method = request.method;
        expect(request.url.path, '/v1/webhooks/endpoints/endpoint-1');
        return _ok(<String, Object?>{'id': 'endpoint-1', 'deleted': true});
      });

      await repository.deleteEndpoint('endpoint-1');

      expect(method, 'DELETE');
    });

    test('lit les livraisons et leur statut', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/webhooks/deliveries');
        return _ok(<Object?>[
          <String, Object?>{
            'id': 'delivery-1',
            'endpoint_id': 'endpoint-1',
            'event': 'project.published',
            'status': 'succeeded',
            'http_status': 200,
            'error_message': null,
            'attempts': 1,
            'created_at': '2026-01-15T10:00:00.000Z',
            'completed_at': '2026-01-15T10:00:01.000Z',
          },
          <String, Object?>{
            'id': 'delivery-2',
            'endpoint_id': 'endpoint-1',
            'event': 'export.completed',
            'status': 'failed',
            'http_status': 500,
            'error_message': 'Le point de rappel a répondu 500.',
            'attempts': 3,
            'created_at': '2026-01-16T10:00:00.000Z',
            'completed_at': null,
          },
        ]);
      });

      final List<WebhookDelivery> deliveries = await repository.deliveries();

      expect(deliveries, hasLength(2));
      expect(deliveries.first.status, WebhookDeliveryStatus.succeeded);
      expect(deliveries.first.httpStatus, 200);
      expect(deliveries.last.status, WebhookDeliveryStatus.failed);
      expect(deliveries.last.isFailed, isTrue);
      expect(deliveries.last.attempts, 3);
    });

    test('rejoue une livraison', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/webhooks/deliveries/delivery-1/replay');
        return _ok(<String, Object?>{
          'id': 'delivery-1',
          'endpoint_id': 'endpoint-1',
          'event': 'project.published',
          'status': 'pending',
          'http_status': null,
          'error_message': null,
          'attempts': 2,
          'created_at': '2026-01-15T10:00:00.000Z',
          'completed_at': null,
        });
      });

      final WebhookDelivery replayed = await repository.replayDelivery(
        'delivery-1',
      );

      expect(replayed.id, 'delivery-1');
      expect(replayed.status, WebhookDeliveryStatus.pending);
      expect(replayed.attempts, 2);
    });

    test('lit le catalogue des événements sur le serveur', () async {
      final ApiWebhookRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/webhooks/events');
        return _ok(<Object?>[
          <String, Object?>{
            'key': 'project.published',
            'label': 'Projet publié',
          },
          <String, Object?>{
            'key': 'export.completed',
            'label': 'Export terminé',
          },
        ]);
      });

      final List<WebhookEvent> events = await repository.availableEvents();

      expect(events, hasLength(2));
      expect(events.first.key, 'project.published');
      expect(events.first.label, 'Projet publié');
    });

    test('traduit le refus de formule', () async {
      final ApiWebhookRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'forbidden',
              'message': "L'API publique et les webhooks sont réservés.",
              'details': <String, Object?>{'feature': 'api_and_webhooks'},
            },
          }),
          403,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.apiKeys(),
        throwsA(isA<StudioPlanRequiredException>()),
      );
    });

    test('remonte une erreur typée quand le serveur refuse', () async {
      final ApiWebhookRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'unauthorized',
              'message': 'La session est fermée.',
            },
          }),
          401,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.apiKeys(),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });

    test('refuse une réponse qui n’est pas une liste', () async {
      final ApiWebhookRepository repository = _repositoryOf(
        (http.Request request) async => _ok(<String, Object?>{'id': 'key-1'}),
      );

      await expectLater(
        repository.apiKeys(),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });

    test('refuse une réponse qui n’est pas un objet', () async {
      final ApiWebhookRepository repository = _repositoryOf(
        (http.Request request) async => _ok(<Object?>['pas', 'un', 'objet']),
      );

      await expectLater(
        repository.rotateApiKey('key-1'),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiWebhookRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiWebhookRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Builds a created answer carrying the envelope of the API.
http.Response _created(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  201,
  headers: <String, String>{'content-type': 'application/json'},
);
