import 'webhook_record.dart';

/// Une page d'enregistrements et le curseur de la page suivante.
///
/// Le curseur est opaque : il encode la clé de tri du dernier élément de la
/// page, pour que le client n'ait pas à connaître l'ordre du tri.
final class WebhookPage<T> {
  /// Crée une page.
  const WebhookPage({
    required this.items,
    required this.total,
    required this.nextCursor,
  });

  /// Les éléments de la page.
  final List<T> items;

  /// Le nombre total d'éléments accessibles au compte.
  final int total;

  /// Le curseur de la page suivante, `null` quand la page est la dernière.
  final String? nextCursor;
}

/// Le port de persistance des clés d'API et des webhooks sortants.
///
/// Le port porte les trois tables de la migration `0011_webhooks.sql` : les
/// clés d'API, les points de rappel et le journal des livraisons. Il ne
/// porte aucune règle métier : la formule du compte, le périmètre des clés
/// et la signature des livraisons vivent dans les services.
abstract interface class WebhookDatabase {
  // ---------------------------------------------------------------------
  // Les clés d'API.
  // ---------------------------------------------------------------------

  /// La clé d'API [id], `null` quand elle n'existe pas.
  Future<ApiKeyRecord?> findApiKey(String id);

  /// La clé d'API dont l'empreinte est [keyHash], `null` quand aucune clé
  /// ne porte cette empreinte.
  Future<ApiKeyRecord?> findApiKeyByHash(String keyHash);

  /// Les clés d'API du compte [userId], les plus récentes d'abord.
  ///
  /// La liste est triée par `created_at` décroissant puis par `id`
  /// croissant : l'ordre est stable et le curseur de pagination s'appuie sur
  /// ce même tri.
  Future<WebhookPage<ApiKeyRecord>> listApiKeys({
    required String userId,
    required int limit,
    String? cursor,
  });

  /// Enregistre une nouvelle clé d'API.
  Future<void> insertApiKey(ApiKeyRecord record);

  /// Met à jour une clé d'API existante.
  Future<void> updateApiKey(ApiKeyRecord record);

  /// Supprime définitivement une clé d'API.
  Future<void> deleteApiKey(String id);

  // ---------------------------------------------------------------------
  // Les points de rappel.
  // ---------------------------------------------------------------------

  /// Le point de rappel [id], `null` quand il n'existe pas.
  Future<WebhookEndpointRecord?> findEndpoint(String id);

  /// Les points de rappel du compte [userId], les plus récents d'abord.
  Future<WebhookPage<WebhookEndpointRecord>> listEndpoints({
    required String userId,
    required int limit,
    String? cursor,
  });

  /// Les points de rappel du compte [userId] abonnés à [event].
  ///
  /// La liste ne porte que les points actifs : un point désactivé ne
  /// reçoit plus rien.
  Future<List<WebhookEndpointRecord>> listSubscribedEndpoints({
    required String userId,
    required String event,
  });

  /// Enregistre un nouveau point de rappel.
  Future<void> insertEndpoint(WebhookEndpointRecord endpoint);

  /// Met à jour un point de rappel existant.
  Future<void> updateEndpoint(WebhookEndpointRecord endpoint);

  /// Supprime définitivement un point de rappel.
  Future<void> deleteEndpoint(String id);

  // ---------------------------------------------------------------------
  // Le journal des livraisons.
  // ---------------------------------------------------------------------

  /// La livraison [id], `null` quand elle n'existe pas.
  Future<WebhookDeliveryRecord?> findDelivery(String id);

  /// Les livraisons du compte [userId], les plus récentes d'abord.
  Future<WebhookPage<WebhookDeliveryRecord>> listDeliveries({
    required String userId,
    required int limit,
    String? cursor,
  });

  /// Enregistre une nouvelle livraison.
  Future<void> insertDelivery(WebhookDeliveryRecord delivery);

  /// Met à jour une livraison existante.
  Future<void> updateDelivery(WebhookDeliveryRecord delivery);
}
