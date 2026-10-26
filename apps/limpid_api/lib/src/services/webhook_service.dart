import 'package:limpid_core/limpid_core.dart';

import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import 'random_secret.dart';
import 'webhook_url_policy.dart';

/// Le nombre maximal de points de rappel qu'un compte peut declarer.
///
/// Chaque point ajoute une attente a chaque evenement livre : un compte
/// sans limite transformerait le service en prologue.
const int maxWebhookEndpointsPerAccount = 20;

/// La durée de transition d'un secret de signature.
///
/// La rotation d'un secret ne doit pas casser le destinataire : pendant
/// cette durée, l'ancien secret est encore accepté et la livraison porte
/// les deux signatures.
const Duration defaultSecretTransition = Duration(hours: 24);

/// Les événements qu'un point de rappel peut recevoir.
enum WebhookEvent {
  /// Un projet du compte a été publié.
  projectPublished('project.published', 'Projet publié'),

  /// Un export du compte est terminé.
  exportCompleted('export.completed', 'Export terminé'),

  /// La formule du compte a changé.
  planChanged('plan.changed', 'Formule changée'),

  /// Un compte a été invité dans une équipe du compte.
  teamInvitationSent('team.invitation_sent', 'Invitation d\'équipe'),

  /// Le compte a atteint la limite d'une fonctionnalité.
  quotaReached('quota.reached', 'Quota atteint');

  /// Crée un événement.
  const WebhookEvent(this.key, this.label);

  /// Le nom technique de l'événement, stable dans la base.
  final String key;

  /// Le libellé de l'événement, en français.
  final String label;

  /// L'événement portant le nom [raw], `null` quand le nom est inconnu.
  static WebhookEvent? parse(String raw) {
    for (final WebhookEvent event in WebhookEvent.values) {
      if (event.key == raw) return event;
    }
    return null;
  }
}

/// Un secret de signature fraîchement renouvelé.
///
/// Le résultat porte le nouveau secret et la fin de la période de
/// transition : l'ancien secret reste accepté jusque-là.
final class RotatedWebhookSecret {
  /// Crée un résultat.
  const RotatedWebhookSecret({
    required this.endpoint,
    required this.secret,
    required this.previousSecretExpiresAt,
  });

  /// Le point de rappel, tel qu'il est désormais enregistré.
  final WebhookEndpointRecord endpoint;

  /// Le nouveau secret, à montrer une seule fois.
  final String secret;

  /// L'instant où l'ancien secret cesse d'être accepté.
  final DateTime? previousSecretExpiresAt;
}

/// Le service des points de rappel et du journal des livraisons.
///
/// Le service porte les règles du domaine : la forme de l'URL de rappel, la
/// rotation du secret et le périmètre des événements. Il ne signe pas les
/// livraisons : l'envoi et la signature sont le rôle du dispatcher.
final class WebhookService {
  /// Crée un service sur le port [database].
  WebhookService({
    required this.database,
    UlidGenerator? generator,
    DateTime Function()? clock,
    this.secretTransition = defaultSecretTransition,
  }) : _generator = generator ?? UlidGenerator(),
       _clock = clock ?? DateTime.now;

  /// Le port de persistance des points de rappel et des livraisons.
  final WebhookDatabase database;
  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// La durée pendant laquelle l'ancien secret reste accepté.
  final Duration secretTransition;

  /// Enregistre un point de rappel pour le compte [userId].
  ///
  /// L'URL doit être absolue et viser un hôte public : [allowInsecure]
  /// n'est vrai qu'en développement, où l'on teste contre un rappel
  /// local. Le secret de signature est renvoyé une seule fois.
  Future<WebhookEndpointRecord> createEndpoint({
    required String userId,
    required String url,
    required Set<WebhookEvent> events,
    required bool allowInsecure,
  }) async {
    if (events.isEmpty) {
      throw const ValidationException(
        field: 'events',
        message: 'Un point de rappel doit s\'abonner à au moins un événement.',
      );
    }
    // Le nombre de points de rappel est borne : chaque point ajoute une
    // attente a chaque evenement, et un compte ne doit pas pouvoir noyer
    // le service.
    final WebhookPage<WebhookEndpointRecord> existing = await database
        .listEndpoints(userId: userId, limit: 1, cursor: null);
    if (existing.total >= maxWebhookEndpointsPerAccount) {
      throw ValidationException(
        field: 'url',
        message:
            'Un compte ne peut pas avoir plus de '
            '$maxWebhookEndpointsPerAccount points de rappel.',
      );
    }

    final String safeUrl = validateCallbackUrl(
      url,
      allowInsecure: allowInsecure,
    );
    final DateTime now = _now();
    final WebhookEndpointRecord endpoint = WebhookEndpointRecord(
      id: _generator.generate().value,
      userId: userId,
      url: safeUrl,
      events: events.map((WebhookEvent event) => event.key).toSet(),
      secret: generateRandomSecret(),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    await database.insertEndpoint(endpoint);
    return endpoint;
  }

  /// Change l'URL ou les événements du point de rappel [endpointId].
  ///
  /// L'URL est revérifiée comme à la création : le compte ne peut pas
  /// faire pointer son rappel vers une adresse que la politique refuse.
  Future<WebhookEndpointRecord> updateEndpoint({
    required String userId,
    required String endpointId,
    required bool allowInsecure,
    String? url,
    Set<WebhookEvent>? events,
  }) async {
    final WebhookEndpointRecord existing = await _requireOwned(
      userId,
      endpointId,
    );
    if (url == null && events == null) {
      throw const ValidationException(
        field: 'body',
        message: 'La modification doit porter une URL ou des événements.',
      );
    }
    if (events != null && events.isEmpty) {
      throw const ValidationException(
        field: 'events',
        message: 'Un point de rappel doit s\'abonner à au moins un événement.',
      );
    }
    final WebhookEndpointRecord updated = existing.copyWith(
      url: url == null
          ? null
          : validateCallbackUrl(url, allowInsecure: allowInsecure),
      events: events?.map((WebhookEvent event) => event.key).toSet(),
      updatedAt: _now(),
    );
    await database.updateEndpoint(updated);
    return updated;
  }

  /// Fait tourner le secret de signature du point de rappel [endpointId].
  ///
  /// Le nouveau secret signe les livraisons dès la rotation. L'ancien
  /// reste accepté pendant la période de transition : les livraisons
  /// portent alors les deux signatures, et le destinataire peut basculer
  /// sans interrompre la intégration.
  Future<RotatedWebhookSecret> rotateSecret({
    required String userId,
    required String endpointId,
  }) async {
    final WebhookEndpointRecord existing = await _requireOwned(
      userId,
      endpointId,
    );
    final DateTime now = _now();
    final DateTime expiresAt = now.add(secretTransition);
    final WebhookEndpointRecord updated = existing.copyWith(
      secret: generateRandomSecret(),
      previousSecret: existing.secret,
      previousSecretExpiresAt: expiresAt,
      updatedAt: now,
    );
    await database.updateEndpoint(updated);
    return RotatedWebhookSecret(
      endpoint: updated,
      secret: updated.secret,
      previousSecretExpiresAt: expiresAt,
    );
  }

  /// Supprime le point de rappel [endpointId] du compte [userId].
  Future<void> deleteEndpoint({
    required String userId,
    required String endpointId,
  }) async {
    await _requireOwned(userId, endpointId);
    await database.deleteEndpoint(endpointId);
  }

  /// Le point de rappel [endpointId] du compte [userId].
  Future<WebhookEndpointRecord> endpointOf({
    required String userId,
    required String endpointId,
  }) {
    return _requireOwned(userId, endpointId);
  }

  /// Les points de rappel du compte [userId], les plus récents d'abord.
  Future<WebhookPage<WebhookEndpointRecord>> listEndpoints({
    required String userId,
    required int limit,
    String? cursor,
  }) {
    return database.listEndpoints(userId: userId, limit: limit, cursor: cursor);
  }

  /// Les livraisons du compte [userId], les plus récentes d'abord.
  Future<WebhookPage<WebhookDeliveryRecord>> listDeliveries({
    required String userId,
    required int limit,
    String? cursor,
  }) {
    return database.listDeliveries(
      userId: userId,
      limit: limit,
      cursor: cursor,
    );
  }

  /// La livraison [deliveryId] du compte [userId].
  Future<WebhookDeliveryRecord> deliveryOf({
    required String userId,
    required String deliveryId,
  }) async {
    final WebhookDeliveryRecord? delivery = await database.findDelivery(
      deliveryId,
    );
    if (delivery == null || delivery.userId != userId) {
      throw const NotFoundException(message: "Cette livraison n'existe pas.");
    }
    return delivery;
  }

  /// Le point de rappel [endpointId] du compte [userId], ou une erreur.
  ///
  /// Un point de rappel qui appartient à un autre compte est refusé comme
  /// s'il n'existait pas : son existence ne se divulgue pas.
  Future<WebhookEndpointRecord> _requireOwned(
    String userId,
    String endpointId,
  ) async {
    final WebhookEndpointRecord? endpoint = await database.findEndpoint(
      endpointId,
    );
    if (endpoint == null || endpoint.userId != userId) {
      throw const NotFoundException(
        message: "Ce point de rappel n'existe pas.",
      );
    }
    return endpoint;
  }

  DateTime _now() => _clock().toUtc();
}
