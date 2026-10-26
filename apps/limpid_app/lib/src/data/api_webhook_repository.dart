import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';

/// Les clés d'API et les points de rappel, servis par l'API.
///
/// Les douze routes de `/v1/api-keys`, `/v1/webhooks/endpoints` et
/// `/v1/webhooks/deliveries` décrivent le cycle de vie des identifiants
/// d'intégration. Le catalogue des événements vient de
/// `GET /v1/webhooks/events` :
/// il est lu sur le serveur, jamais figé ici.
///
/// Le dépôt ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`, ou
/// `StudioPlanRequiredException` quand la formule du compte n'ouvre pas
/// l'API.
final class ApiWebhookRepository implements WebhookRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiWebhookRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  Future<List<ApiKey>> apiKeys() async {
    final Object? payload = await _read(() => client.get('/v1/api-keys'));
    return _listOf(payload).map(_apiKeyOf).toList(growable: false);
  }

  @override
  Future<CreatedApiKey> createApiKey({
    required String name,
    required Set<ApiKeyScope> scopes,
  }) async {
    final Object? payload = await _read(
      () => client.post(
        '/v1/api-keys',
        body: <String, Object?>{
          'name': name,
          'scopes': <String>[for (final ApiKeyScope scope in scopes) scope.key],
        },
      ),
    );
    final Map<String, Object?> data = _objectOf(payload);
    return CreatedApiKey(
      key: _apiKeyOf(data),
      secret: _stringOf(data['secret']) ?? '',
    );
  }

  @override
  Future<CreatedApiKey> rotateApiKey(String keyId) async {
    final Object? payload = await _read(
      () => client.post('/v1/api-keys/$keyId/rotate'),
    );
    final Map<String, Object?> data = _objectOf(payload);
    return CreatedApiKey(
      key: _apiKeyOf(data),
      secret: _stringOf(data['secret']) ?? '',
    );
  }

  @override
  Future<void> deleteApiKey(String keyId) async {
    await _read(() => client.delete('/v1/api-keys/$keyId'));
  }

  @override
  Future<List<WebhookEndpoint>> endpoints() async {
    final Object? payload = await _read(
      () => client.get('/v1/webhooks/endpoints'),
    );
    return _listOf(payload).map(_endpointOf).toList(growable: false);
  }

  @override
  Future<WebhookEndpointSecret> createEndpoint({
    required String url,
    required Set<String> events,
  }) async {
    final Object? payload = await _read(
      () => client.post(
        '/v1/webhooks/endpoints',
        body: <String, Object?>{
          'url': url,
          'events': events.toList(growable: false),
        },
      ),
    );
    final Map<String, Object?> data = _objectOf(payload);
    return WebhookEndpointSecret(
      endpoint: _endpointOf(data),
      secret: _stringOf(data['secret']) ?? '',
    );
  }

  @override
  Future<WebhookEndpoint> updateEndpoint(
    String endpointId, {
    String? url,
    Set<String>? events,
  }) async {
    final Object? payload = await _read(
      () => client.patch(
        '/v1/webhooks/endpoints/$endpointId',
        body: <String, Object?>{
          'url': ?url,
          if (events != null) 'events': events.toList(growable: false),
        },
      ),
    );
    return _endpointOf(_objectOf(payload));
  }

  @override
  Future<WebhookEndpointSecret> rotateEndpointSecret(String endpointId) async {
    final Object? payload = await _read(
      () => client.post('/v1/webhooks/endpoints/$endpointId/rotate-secret'),
    );
    final Map<String, Object?> data = _objectOf(payload);
    return WebhookEndpointSecret(
      endpoint: _endpointOf(data),
      secret: _stringOf(data['secret']) ?? '',
    );
  }

  @override
  Future<void> deleteEndpoint(String endpointId) async {
    await _read(() => client.delete('/v1/webhooks/endpoints/$endpointId'));
  }

  @override
  Future<List<WebhookDelivery>> deliveries() async {
    final Object? payload = await _read(
      () => client.get('/v1/webhooks/deliveries'),
    );
    return _listOf(payload).map(_deliveryOf).toList(growable: false);
  }

  @override
  Future<WebhookDelivery> replayDelivery(String deliveryId) async {
    final Object? payload = await _read(
      () => client.post('/v1/webhooks/deliveries/$deliveryId/replay'),
    );
    return _deliveryOf(_objectOf(payload));
  }

  @override
  Future<List<WebhookEvent>> availableEvents() async {
    final Object? payload = await _read(
      () => client.get('/v1/webhooks/events'),
    );
    return _listOf(payload).map(_eventOf).toList(growable: false);
  }

  /// Lit la charge d'une réponse et traduit le refus de formule.
  ///
  /// Le serveur répond `403 forbidden` et nomme la fonctionnalité
  /// `api_and_webhooks` dans les détails : l'écran doit le dire, et non
  /// montrer une liste vide qui ferait croire que le compte n'a rien.
  Future<Object?> _read(Future<Object?> Function() call) async {
    try {
      return await call();
    } on ApiUnauthorizedException catch (error) {
      if (error.statusCode == _forbiddenStatus) {
        throw const StudioPlanRequiredException();
      }
      rethrow;
    }
  }

  /// La clé d'API d'une réponse du serveur.
  static ApiKey _apiKeyOf(Map<String, Object?> data) {
    return ApiKey(
      id: _stringOf(data['id']) ?? '',
      name: _stringOf(data['name']) ?? '',
      scopes: _scopesOf(data['scopes']),
      isActive: _boolOf(data['is_active']),
      isRevoked: _boolOf(data['is_revoked']),
      createdAt: _momentOf(data['created_at']) ?? DateTime.now().toUtc(),
      rotatedAt: _momentOf(data['rotated_at']),
      revokedAt: _momentOf(data['revoked_at']),
      lastUsedAt: _momentOf(data['last_used_at']),
    );
  }

  /// Le point de rappel d'une réponse du serveur.
  static WebhookEndpoint _endpointOf(Map<String, Object?> data) {
    return WebhookEndpoint(
      id: _stringOf(data['id']) ?? '',
      url: _stringOf(data['url']) ?? '',
      events: _stringsOf(data['events']),
      isActive: _boolOf(data['is_active']),
      hasPreviousSecret: _boolOf(data['has_previous_secret']),
      previousSecretExpiresAt: _momentOf(data['previous_secret_expires_at']),
      createdAt: _momentOf(data['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _momentOf(data['updated_at']) ?? DateTime.now().toUtc(),
    );
  }

  /// La livraison d'une réponse du serveur.
  static WebhookDelivery _deliveryOf(Map<String, Object?> data) {
    return WebhookDelivery(
      id: _stringOf(data['id']) ?? '',
      endpointId: _stringOf(data['endpoint_id']) ?? '',
      event: _stringOf(data['event']) ?? '',
      status: WebhookDeliveryStatus.fromKey(_stringOf(data['status']) ?? ''),
      httpStatus: _intOf(data['http_status']),
      errorMessage: _stringOf(data['error_message']),
      attempts: _intOf(data['attempts']) ?? 0,
      createdAt: _momentOf(data['created_at']) ?? DateTime.now().toUtc(),
      completedAt: _momentOf(data['completed_at']),
    );
  }

  /// L'événement d'une réponse du serveur.
  static WebhookEvent _eventOf(Map<String, Object?> data) {
    final String key = _stringOf(data['key']) ?? '';
    return WebhookEvent(key: key, label: _stringOf(data['label']) ?? key);
  }

  /// Les périmètres d'une réponse du serveur.
  ///
  /// Un périmètre que le serveur ne publie pas est ignoré : l'écran montre
  /// ce qu'il connaît, jamais un nom inventé.
  static Set<ApiKeyScope> _scopesOf(Object? value) {
    if (value is! List<dynamic>) return const <ApiKeyScope>{};
    final Set<ApiKeyScope> scopes = <ApiKeyScope>{};
    for (final Object? item in value) {
      if (item is! String) continue;
      final ApiKeyScope? scope = ApiKeyScope.fromKey(item);
      if (scope != null) scopes.add(scope);
    }
    return Set<ApiKeyScope>.unmodifiable(scopes);
  }

  /// Les événements d'une réponse du serveur.
  static Set<String> _stringsOf(Object? value) {
    if (value is! List<dynamic>) return const <String>{};
    return Set<String>.unmodifiable(<String>[
      for (final Object? item in value)
        if (item is String) item,
    ]);
  }

  /// La charge d'une réponse, quand elle est une liste.
  static List<Map<String, Object?>> _listOf(Object? value) {
    if (value is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the expected list.',
      );
    }
    return <Map<String, Object?>>[
      for (final Object? item in value) _objectOf(item),
    ];
  }

  /// Le corps de la réponse, quand il est un objet.
  static Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static bool _boolOf(Object? value) {
    if (value is bool) return value;
    return false;
  }

  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// Le statut HTTP du refus de formule.
const int _forbiddenStatus = 403;
