/// Les clés d'API et les points de rappel de l'auteur.
///
/// Le contrat vit dans la couche domaine : les écrans le nomment,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
///
/// Le secret d'une clé et le secret de signature d'un point de rappel sont
/// **rendus une seule fois** : le serveur ne les rend plus jamais. L'écran
/// les montre, il ne les garde pas.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Le périmètre d'une clé d'API.
///
/// Le périmètre borne ce que la clé peut faire : une clé de lecture lit les
/// ressources du compte, une clé d'écriture les modifie.
enum ApiKeyScope {
  /// Lire les ressources du compte : points de rappel, journal des
  /// livraisons.
  read('read'),

  /// Créer et modifier les ressources du compte.
  write('write');

  /// Crée un périmètre.
  const ApiKeyScope(this.key);

  /// Le nom technique du périmètre, stable dans la base.
  final String key;

  /// Le périmètre portant le nom [raw], `null` quand le nom est inconnu.
  ///
  /// Un nom inconnu ne fait jamais échouer la lecture : l'écran montre alors
  /// le périmètre le plus prudent, la lecture.
  static ApiKeyScope? fromKey(String raw) {
    for (final ApiKeyScope scope in ApiKeyScope.values) {
      if (scope.key == raw) return scope;
    }
    return null;
  }
}

/// Une clé d'API du compte.
///
/// La clé elle-même n'est jamais là : la base n'en garde que l'empreinte.
/// L'écran ne connaît que le nom, le périmètre et les dates.
final class ApiKey {
  /// Crée une clé.
  const ApiKey({
    required this.id,
    required this.name,
    required this.scopes,
    required this.isActive,
    required this.isRevoked,
    required this.createdAt,
    this.rotatedAt,
    this.revokedAt,
    this.lastUsedAt,
  });

  /// L'identifiant de la clé.
  ///
  /// L'identifiant ne change jamais : une clé renouvelée garde son
  /// identité, donc les intégrations qui la référencent continuent de
  /// fonctionner.
  final String id;

  /// Le nom donné à la clé, pour que l'auteur la retrouve dans sa liste.
  final String name;

  /// Le périmètre de la clé.
  final Set<ApiKeyScope> scopes;

  /// Indique si la clé est active.
  final bool isActive;

  /// Indique si la clé a été révoquée.
  final bool isRevoked;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant du dernier renouvellement, `null` quand la clé n'a jamais
  /// été renouvelée.
  final DateTime? rotatedAt;

  /// L'instant de la révocation, `null` quand la clé est vivante.
  final DateTime? revokedAt;

  /// L'instant du dernier usage, `null` quand la clé n'a jamais servi.
  final DateTime? lastUsedAt;

  /// Indique si la clé peut encore servir à authentifier un appel.
  bool get isUsable => isActive && !isRevoked;
}

/// Une clé d'API et son secret, au moment de la création ou du
/// renouvellement.
///
/// Le secret n'existe que dans cette réponse : l'application le montre une
/// fois, elle ne le garde pas.
final class CreatedApiKey {
  /// Crée un résultat.
  const CreatedApiKey({required this.key, required this.secret});

  /// La clé telle que le serveur l'a enregistrée.
  final ApiKey key;

  /// Le secret de la clé, à montrer une seule fois.
  final String secret;
}

/// Un point de rappel des webhooks sortants.
///
/// Le point porte l'adresse déclarée par l'auteur et la liste des
/// événements auxquels il est abonné. Le secret de signature n'y figure
/// jamais : il n'est rendu qu'à la création et au renouvellement.
final class WebhookEndpoint {
  /// Crée un point de rappel.
  const WebhookEndpoint({
    required this.id,
    required this.url,
    required this.events,
    required this.isActive,
    required this.hasPreviousSecret,
    required this.createdAt,
    required this.updatedAt,
    this.previousSecretExpiresAt,
  });

  /// L'identifiant du point de rappel.
  final String id;

  /// L'adresse de rappel.
  final String url;

  /// Les événements auxquels le point est abonné.
  ///
  /// Ce sont les noms techniques des événements, tels que le serveur les
  /// écrit : la liste des événements possibles est lue sur le serveur, elle
  /// n'est jamais figée dans l'application.
  final Set<String> events;

  /// Indique si le point de rappel reçoit encore des livraisons.
  final bool isActive;

  /// Indique si un secret précédent est encore accepté.
  final bool hasPreviousSecret;

  /// L'instant où le secret précédent cesse d'être accepté.
  final DateTime? previousSecretExpiresAt;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant de la dernière modification.
  final DateTime updatedAt;
}

/// Un point de rappel et son secret de signature, au moment de la création
/// ou du renouvellement.
///
/// Le secret n'existe que dans cette réponse : l'application le montre une
/// fois, elle ne le garde pas.
final class WebhookEndpointSecret {
  /// Crée un résultat.
  const WebhookEndpointSecret({required this.endpoint, required this.secret});

  /// Le point de rappel, tel que le serveur l'a enregistré.
  final WebhookEndpoint endpoint;

  /// Le secret de signature, à montrer une seule fois.
  final String secret;
}

/// Le statut d'une tentative de livraison.
///
/// Les trois statuts sont ceux de la base : une livraison est en attente,
/// elle a abouti, ou elle a échoué.
enum WebhookDeliveryStatus {
  /// La livraison a été préparée mais son issue n'est pas encore connue.
  pending('pending'),

  /// Le point de rappel a répondu avec un code de succès.
  succeeded('succeeded'),

  /// Le point de rappel a répondu avec un code d'erreur, ou n'a pas
  /// répondu.
  failed('failed');

  /// Crée un statut.
  const WebhookDeliveryStatus(this.key);

  /// Le nom technique du statut, stable dans la base.
  final String key;

  /// Le statut portant le nom [raw].
  ///
  /// Un nom inconnu ne fait jamais échouer la lecture : l'écran montre alors
  /// le statut le plus prudent, la livraison en attente.
  static WebhookDeliveryStatus fromKey(String raw) {
    for (final WebhookDeliveryStatus status in WebhookDeliveryStatus.values) {
      if (status.key == raw) return status;
    }
    return WebhookDeliveryStatus.pending;
  }
}

/// La trace d'une tentative de livraison.
///
/// La trace est la preuve de la livraison : elle porte le statut, le code
/// HTTP répondu et l'instant.
final class WebhookDelivery {
  /// Crée une livraison.
  const WebhookDelivery({
    required this.id,
    required this.endpointId,
    required this.event,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.httpStatus,
    this.errorMessage,
    this.completedAt,
  });

  /// L'identifiant de la livraison.
  ///
  /// L'identifiant est celui de l'événement : un rejeu renvoie la même
  /// charge, donc le même identifiant, et le destinataire peut écarter le
  /// doublon.
  final String id;

  /// Le point de rappel qui a reçu la livraison.
  final String endpointId;

  /// L'événement livré.
  final String event;

  /// Le statut de la livraison.
  final WebhookDeliveryStatus status;

  /// Le code HTTP répondu par le point de rappel, `null` quand il n'a pas
  /// répondu.
  final int? httpStatus;

  /// Le motif de l'échec, `null` quand la livraison a abouti.
  final String? errorMessage;

  /// Le nombre de tentatives, rejeu compris.
  final int attempts;

  /// L'instant de la préparation de la livraison.
  final DateTime createdAt;

  /// L'instant où l'issue de la tentative a été connue.
  final DateTime? completedAt;

  /// Indique si la livraison a échoué.
  bool get isFailed => status == WebhookDeliveryStatus.failed;
}

/// Un événement auquel un point de rappel peut s'abonner.
///
/// Le catalogue des événements est lu **sur le serveur** : l'application ne
/// le fige pas, elle suit ce que le serveur publie.
final class WebhookEvent {
  /// Crée un événement.
  const WebhookEvent({required this.key, required this.label});

  /// Le nom technique de l'événement, celui que le serveur attend dans le
  /// corps d'un point de rappel.
  final String key;

  /// Le libellé de l'événement, tel que le serveur l'écrit.
  final String label;
}

/// L'API et les webhooks sont réservés à la formule Studio.
///
/// Le serveur répond `403 forbidden` et nomme la fonctionnalité dans les
/// détails de l'erreur. L'écran doit le dire : une liste vide ferait croire
/// que le compte n'a rien, alors que le compte n'a pas le droit de lire.
final class StudioPlanRequiredException implements Exception {
  /// Crée l'erreur.
  const StudioPlanRequiredException([this.message = defaultStudioPlanMessage]);

  /// L'explication technique, destinée aux journaux.
  final String message;

  @override
  String toString() => 'StudioPlanRequiredException: $message';
}

/// L'explication technique du refus de formule.
const String defaultStudioPlanMessage =
    'The API and the webhooks are reserved to the Studio plan.';

/// Le port des clés d'API et des points de rappel.
///
/// L'écran lit ce port et n'atteint jamais le serveur. La doublure par
/// défaut refuse les appels et dit pourquoi : un écran ne présente jamais
/// une clé, un point de rappel ou une livraison qu'il n'a pas lus.
abstract interface class WebhookRepository {
  /// Les clés d'API du compte.
  ///
  /// Le secret n'y figure jamais : il n'est rendu qu'à la création et au
  /// renouvellement.
  Future<List<ApiKey>> apiKeys();

  /// Crée une clé d'API nommée [name] et rend son secret, **une seule
  /// fois**.
  Future<CreatedApiKey> createApiKey({
    required String name,
    required Set<ApiKeyScope> scopes,
  });

  /// Renouvelle le secret de la clé [keyId] et rend le nouveau secret,
  /// **une seule fois**.
  Future<CreatedApiKey> rotateApiKey(String keyId);

  /// Supprime la clé [keyId].
  Future<void> deleteApiKey(String keyId);

  /// Les points de rappel du compte.
  Future<List<WebhookEndpoint>> endpoints();

  /// Crée un point de rappel sur [url] et rend son secret de signature,
  /// **une seule fois**.
  Future<WebhookEndpointSecret> createEndpoint({
    required String url,
    required Set<String> events,
  });

  /// Modifie le point de rappel [endpointId].
  ///
  /// Les champs absents ne changent pas : une adresse nulle et une liste
  /// d'événements nulle laissent le point de rappel intact.
  Future<WebhookEndpoint> updateEndpoint(
    String endpointId, {
    String? url,
    Set<String>? events,
  });

  /// Renouvelle le secret de signature du point de rappel [endpointId] et
  /// rend le nouveau secret, **une seule fois**.
  Future<WebhookEndpointSecret> rotateEndpointSecret(String endpointId);

  /// Supprime le point de rappel [endpointId].
  Future<void> deleteEndpoint(String endpointId);

  /// Les livraisons du compte, les plus récentes d'abord.
  Future<List<WebhookDelivery>> deliveries();

  /// Rejoue la livraison [deliveryId] et rend son nouvel état.
  Future<WebhookDelivery> replayDelivery(String deliveryId);

  /// Les événements auxquels un point de rappel peut s'abonner.
  ///
  /// La liste est lue **sur le serveur** : elle suit le serveur au lieu
  /// d'être figée dans l'application.
  Future<List<WebhookEvent>> availableEvents();
}

/// Un [WebhookRepository] qui ne peut pas atteindre le serveur.
///
/// Le mode démonstration n'a pas de service distant : l'écran le dit au
/// lieu de montrer une liste vide qui ferait croire que le compte n'a
/// rien.
final class UnavailableWebhookRepository
    implements WebhookRepository, UnavailableService {
  /// Crée le dépôt indisponible.
  const UnavailableWebhookRepository();

  @override
  Future<List<ApiKey>> apiKeys() async =>
      throw const ServiceUnavailableException();

  @override
  Future<CreatedApiKey> createApiKey({
    required String name,
    required Set<ApiKeyScope> scopes,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CreatedApiKey> rotateApiKey(String keyId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<void> deleteApiKey(String keyId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<WebhookEndpoint>> endpoints() async =>
      throw const ServiceUnavailableException();

  @override
  Future<WebhookEndpointSecret> createEndpoint({
    required String url,
    required Set<String> events,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<WebhookEndpoint> updateEndpoint(
    String endpointId, {
    String? url,
    Set<String>? events,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<WebhookEndpointSecret> rotateEndpointSecret(String endpointId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<void> deleteEndpoint(String endpointId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<WebhookDelivery>> deliveries() async =>
      throw const ServiceUnavailableException();

  @override
  Future<WebhookDelivery> replayDelivery(String deliveryId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<WebhookEvent>> availableEvents() async =>
      throw const ServiceUnavailableException();
}

/// Le dépôt des clés d'API et des points de rappel.
///
/// Le point de composition le remplace par l'implémentation de la couche
/// données. Le défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais une clé, un point de rappel ou une livraison qu'il n'a
/// pas lus.
final Provider<WebhookRepository> webhookRepositoryProvider =
    Provider<WebhookRepository>(
      (Ref ref) => const UnavailableWebhookRepository(),
    );
