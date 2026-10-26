import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';

void main() {
  group('UnavailableWebhookRepository', () {
    const UnavailableWebhookRepository repository =
        UnavailableWebhookRepository();

    test('refuse de lire les clés', () async {
      await expectLater(
        repository.apiKeys(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de créer une clé', () async {
      await expectLater(
        repository.createApiKey(
          name: 'Intégration',
          scopes: <ApiKeyScope>{ApiKeyScope.read},
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de renouveler une clé', () async {
      await expectLater(
        repository.rotateApiKey('key-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de supprimer une clé', () async {
      await expectLater(
        repository.deleteApiKey('key-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de lire les points de réception', () async {
      await expectLater(
        repository.endpoints(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de créer un point de réception', () async {
      await expectLater(
        repository.createEndpoint(
          url: 'https://exemple.test/limpid',
          events: <String>{'project.published'},
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de modifier un point de réception', () async {
      await expectLater(
        repository.updateEndpoint('endpoint-1', url: 'https://exemple.test'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de renouveler un secret de signature', () async {
      await expectLater(
        repository.rotateEndpointSecret('endpoint-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de supprimer un point de réception', () async {
      await expectLater(
        repository.deleteEndpoint('endpoint-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de lire les livraisons', () async {
      await expectLater(
        repository.deliveries(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de rejouer une livraison', () async {
      await expectLater(
        repository.replayDelivery('delivery-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de lire le catalogue des événements', () async {
      await expectLater(
        repository.availableEvents(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('se déclare comme un service indisponible', () {
      expect(repository, isA<UnavailableService>());
    });
  });

  group('webhookRepositoryProvider', () {
    test('vaut la doublure indisponible par défaut', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(webhookRepositoryProvider),
        isA<UnavailableWebhookRepository>(),
      );
    });
  });

  group('ApiKeyScope', () {
    test('lit les noms que le serveur écrit', () {
      expect(ApiKeyScope.fromKey('read'), ApiKeyScope.read);
      expect(ApiKeyScope.fromKey('write'), ApiKeyScope.write);
    });

    test('ignore un nom inconnu', () {
      expect(ApiKeyScope.fromKey('admin'), isNull);
    });
  });

  group('WebhookDeliveryStatus', () {
    test('lit les noms que le serveur écrit', () {
      expect(
        WebhookDeliveryStatus.fromKey('pending'),
        WebhookDeliveryStatus.pending,
      );
      expect(
        WebhookDeliveryStatus.fromKey('succeeded'),
        WebhookDeliveryStatus.succeeded,
      );
      expect(
        WebhookDeliveryStatus.fromKey('failed'),
        WebhookDeliveryStatus.failed,
      );
    });

    test('reste prudent devant un nom inconnu', () {
      expect(
        WebhookDeliveryStatus.fromKey('unknown'),
        WebhookDeliveryStatus.pending,
      );
    });
  });

  group('StudioPlanRequiredException', () {
    test('porte une explication technique', () {
      const StudioPlanRequiredException error = StudioPlanRequiredException();

      expect(error.message, isNotEmpty);
      expect(error.toString(), contains('StudioPlanRequiredException'));
    });
  });
}
