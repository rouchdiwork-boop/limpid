import 'package:limpid_app/src/domain/webhook_repository.dart';

/// The key the fake serves.
final ApiKey fakeApiKey = ApiKey(
  id: 'key-1',
  name: 'Intégration',
  scopes: <ApiKeyScope>{ApiKeyScope.read},
  isActive: true,
  isRevoked: false,
  createdAt: DateTime.utc(2026, 1, 15),
  lastUsedAt: null,
);

/// A second key, revoked by its author.
final ApiKey fakeRevokedApiKey = ApiKey(
  id: 'key-2',
  name: 'Ancienne intégration',
  scopes: <ApiKeyScope>{ApiKeyScope.read, ApiKeyScope.write},
  isActive: false,
  isRevoked: true,
  createdAt: DateTime.utc(2025, 11, 2),
  revokedAt: DateTime.utc(2026, 1, 3),
);

/// The secret the fake renders.
const String fakeApiKeySecret = 'lk.key-1.s3cr3t';

/// The endpoint the fake serves.
final WebhookEndpoint fakeEndpoint = WebhookEndpoint(
  id: 'endpoint-1',
  url: 'https://exemple.test/limpid',
  events: <String>{'project.published'},
  isActive: true,
  hasPreviousSecret: false,
  createdAt: DateTime.utc(2026, 1, 15),
  updatedAt: DateTime.utc(2026, 1, 15),
);

/// The signing secret the fake renders.
const String fakeEndpointSecret = 'whsec_fake_secret';

/// The delivery the fake serves.
final WebhookDelivery fakeDelivery = WebhookDelivery(
  id: 'delivery-1',
  endpointId: 'endpoint-1',
  event: 'project.published',
  status: WebhookDeliveryStatus.succeeded,
  httpStatus: 200,
  attempts: 1,
  createdAt: DateTime.utc(2026, 1, 15),
  completedAt: DateTime.utc(2026, 1, 15),
);

/// A delivery that failed.
final WebhookDelivery fakeFailedDelivery = WebhookDelivery(
  id: 'delivery-2',
  endpointId: 'endpoint-1',
  event: 'export.completed',
  status: WebhookDeliveryStatus.failed,
  errorMessage: 'Le point de rappel a répondu 500.',
  attempts: 3,
  createdAt: DateTime.utc(2026, 1, 16),
);

/// The catalogue of events the fake serves.
const List<WebhookEvent> fakeEvents = <WebhookEvent>[
  WebhookEvent(key: 'project.published', label: 'Projet publié'),
  WebhookEvent(key: 'export.completed', label: 'Export terminé'),
];

/// A [WebhookRepository] the test drives by hand.
///
/// The fake holds the state of the account, the secrets it renders and the
/// trace of what the author asked for : it reads nothing from the server.
final class FakeWebhookRepository implements WebhookRepository {
  /// Creates a repository.
  FakeWebhookRepository({
    List<ApiKey>? keys,
    List<WebhookEndpoint>? endpoints,
    List<WebhookDelivery>? deliveries,
    List<WebhookEvent>? events,
  }) : keys = <ApiKey>[...?keys],
       endpointList = <WebhookEndpoint>[...?endpoints],
       deliveryList = <WebhookDelivery>[...?deliveries],
       events = <WebhookEvent>[...?events];

  /// The keys the repository serves.
  final List<ApiKey> keys;

  /// The endpoints the repository serves.
  final List<WebhookEndpoint> endpointList;

  /// The deliveries the repository serves.
  final List<WebhookDelivery> deliveryList;

  /// The events the repository serves.
  final List<WebhookEvent> events;

  /// The error every operation throws when it is set.
  Object? error;

  /// The error the reading of the catalogue of events throws when it is set.
  Object? eventsError;

  /// The secret the creation and the rotation of a key render.
  String keySecret = fakeApiKeySecret;

  /// The secret the creation and the rotation of an endpoint render.
  String endpointSecret = fakeEndpointSecret;

  /// The keys the author created, with their scope.
  final List<(String, Set<ApiKeyScope>)> createdKeys =
      <(String, Set<ApiKeyScope>)>[];

  /// The identifiers of the keys the author renewed.
  final List<String> rotatedKeys = <String>[];

  /// The identifiers of the keys the author deleted.
  final List<String> deletedKeys = <String>[];

  /// The endpoints the author created, with their events.
  final List<(String, Set<String>)> createdEndpoints =
      <(String, Set<String>)>[];

  /// The modifications the author asked for.
  final List<(String, String?, Set<String>?)> updatedEndpoints =
      <(String, String?, Set<String>?)>[];

  /// The identifiers of the endpoints whose secret was renewed.
  final List<String> rotatedEndpoints = <String>[];

  /// The identifiers of the endpoints the author deleted.
  final List<String> deletedEndpoints = <String>[];

  /// The identifiers of the deliveries the author replayed.
  final List<String> replayed = <String>[];

  @override
  Future<List<ApiKey>> apiKeys() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<ApiKey>.unmodifiable(keys);
  }

  @override
  Future<CreatedApiKey> createApiKey({
    required String name,
    required Set<ApiKeyScope> scopes,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    createdKeys.add((name, scopes));
    final ApiKey key = ApiKey(
      id: 'key-${keys.length + 1}',
      name: name,
      scopes: scopes,
      isActive: true,
      isRevoked: false,
      createdAt: DateTime.utc(2026, 2, 1),
    );
    keys.add(key);
    return CreatedApiKey(key: key, secret: keySecret);
  }

  @override
  Future<CreatedApiKey> rotateApiKey(String keyId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    rotatedKeys.add(keyId);
    return CreatedApiKey(key: fakeApiKey, secret: keySecret);
  }

  @override
  Future<void> deleteApiKey(String keyId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    deletedKeys.add(keyId);
    keys.removeWhere((ApiKey key) => key.id == keyId);
  }

  @override
  Future<List<WebhookEndpoint>> endpoints() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<WebhookEndpoint>.unmodifiable(endpointList);
  }

  @override
  Future<WebhookEndpointSecret> createEndpoint({
    required String url,
    required Set<String> events,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    createdEndpoints.add((url, events));
    final WebhookEndpoint endpoint = WebhookEndpoint(
      id: 'endpoint-${endpointList.length + 1}',
      url: url,
      events: events,
      isActive: true,
      hasPreviousSecret: false,
      createdAt: DateTime.utc(2026, 2, 1),
      updatedAt: DateTime.utc(2026, 2, 1),
    );
    endpointList.add(endpoint);
    return WebhookEndpointSecret(endpoint: endpoint, secret: endpointSecret);
  }

  @override
  Future<WebhookEndpoint> updateEndpoint(
    String endpointId, {
    String? url,
    Set<String>? events,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    updatedEndpoints.add((endpointId, url, events));
    return fakeEndpoint;
  }

  @override
  Future<WebhookEndpointSecret> rotateEndpointSecret(String endpointId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    rotatedEndpoints.add(endpointId);
    return WebhookEndpointSecret(
      endpoint: fakeEndpoint,
      secret: endpointSecret,
    );
  }

  @override
  Future<void> deleteEndpoint(String endpointId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    deletedEndpoints.add(endpointId);
    endpointList.removeWhere(
      (WebhookEndpoint endpoint) => endpoint.id == endpointId,
    );
  }

  @override
  Future<List<WebhookDelivery>> deliveries() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<WebhookDelivery>.unmodifiable(deliveryList);
  }

  @override
  Future<WebhookDelivery> replayDelivery(String deliveryId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    replayed.add(deliveryId);
    return fakeDelivery;
  }

  @override
  Future<List<WebhookEvent>> availableEvents() async {
    final Object? failure = eventsError ?? error;
    if (failure != null) throw failure;
    return List<WebhookEvent>.unmodifiable(events);
  }
}
