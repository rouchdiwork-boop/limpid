import 'dart:io';

import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

/// La surface d'éjection des rappels.
///
/// Un rappel est une adresse **écrite** par le serveur : la charge de
/// l'événement y part. Une adresse qui désigne le réseau du déploiement
/// transforme le rappel en vecteur d'éjection vers l'infrastructure.
void main() {
  group('La politique des URL de rappel', () {
    test('refuse les adresses privées, même déguisées', () {
      // Les notations ci-dessous ne sont pas des erreurs de frappe : ce
      // sont des adresses valides pour le résolveur, et des adresses
      // privées pour la machine.
      for (final String host in <String>[
        '127.0.0.1',
        '127.1',
        '2130706433',
        '0x7f.0.0.1',
        '0177.0.0.1',
        '10.0.0.5',
        '192.168.1.1',
        '169.254.169.254',
        '100.64.0.1',
        '::1',
        '::ffff:127.0.0.1',
        '::ffff:169.254.169.254',
        '::ffff:10.0.0.5',
        'localhost',
        'rappel.local',
        'rappel.internal',
      ]) {
        expect(
          isPrivateHost(host),
          isTrue,
          reason: 'l\'hôte « $host » doit être refusé',
        );
      }
    });

    test('laisse passer les adresses publiques', () {
      for (final String host in <String>[
        'rappel.exemple.com',
        '8.8.8.8',
        '203.0.113.7',
        '2606:4700:4700::1111',
      ]) {
        expect(
          isPrivateHost(host),
          isFalse,
          reason: 'l\'hôte « $host » doit être accepté',
        );
      }
    });

    test('refuse l\'URL d\'un hôte privé en production', () {
      expect(
        () => validateCallbackUrl(
          'https://[::ffff:169.254.169.254]/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => validateCallbackUrl(
          'https://2130706433/rappel',
          allowInsecure: false,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepte l\'URL d\'un hôte privé en développement', () {
      // Le profil de développement teste la livraison contre un rappel
      // local : c'est la seule raison pour laquelle la règle s'assouplit.
      expect(
        validateCallbackUrl(
          'http://127.0.0.1:9000/rappel',
          allowInsecure: true,
        ),
        isNotEmpty,
      );
    });
  });

  group('La livraison', () {
    test('ne suit jamais une redirection', () async {
      // Le serveur de l'auteur repond 303 et renvoie vers une autre
      // adresse. Le suivre transformerait la livraison en lecture vers
      // cette adresse : c'est exactement ce qu'on ne veut pas.
      final HttpServer cible = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      int appelsCible = 0;
      cible.listen((HttpRequest request) async {
        appelsCible += 1;
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      final HttpServer rappel = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      rappel.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.seeOther;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${cible.port}/interne',
        );
        await request.response.close();
      });

      final WebhookDispatcher dispatcher = WebhookDispatcher(
        database: InMemoryWebhookDatabase(),
        allowPrivateHosts: true,
      );
      await dispatcher.database.insertEndpoint(
        WebhookEndpointRecord(
          id: 'endpoint-1',
          userId: 'user-1',
          url: 'http://127.0.0.1:${rappel.port}/rappel',
          events: <String>{WebhookEvent.projectPublished.key},
          secret: 'secret',
          isActive: true,
          createdAt: DateTime.utc(2026, 10, 26),
          updatedAt: DateTime.utc(2026, 10, 26),
        ),
      );

      final List<WebhookDeliveryRecord> deliveries = await dispatcher.dispatch(
        userId: 'user-1',
        event: WebhookEvent.projectPublished,
        data: <String, Object?>{'project_id': 'project-1'},
      );

      expect(appelsCible, 0, reason: 'la redirection ne doit pas etre suivie');
      expect(deliveries, hasLength(1));
      expect(deliveries.first.status, WebhookDeliveryStatus.failed);
      expect(deliveries.first.httpStatus, HttpStatus.seeOther);

      await rappel.close(force: true);
      await cible.close(force: true);
    });

    test('refuse une adresse qui se résout vers le réseau interne', () async {
      final WebhookDispatcher dispatcher = WebhookDispatcher(
        database: InMemoryWebhookDatabase(),
      );
      await dispatcher.database.insertEndpoint(
        WebhookEndpointRecord(
          id: 'endpoint-1',
          userId: 'user-1',
          url: 'https://rappel.invalid/hook',
          events: <String>{WebhookEvent.projectPublished.key},
          secret: 'secret',
          isActive: true,
          createdAt: DateTime.utc(2026, 10, 26),
          updatedAt: DateTime.utc(2026, 10, 26),
        ),
      );

      // Le nom « rappel.invalid » ne se résout jamais — le domaine
      // « .invalid » est réservé pour cela : le test ne touche pas le
      // réseau. Le rappel est refusé plutôt que d'écrire dans le vide, et
      // le refus est **dit**.
      final List<WebhookDeliveryRecord> deliveries = await dispatcher.dispatch(
        userId: 'user-1',
        event: WebhookEvent.projectPublished,
        data: <String, Object?>{'project_id': 'project-1'},
      );

      expect(deliveries, hasLength(1));
      expect(deliveries.first.status, WebhookDeliveryStatus.failed);
      expect(deliveries.first.errorMessage, contains('ne se resout pas'));
    });
  });
}
