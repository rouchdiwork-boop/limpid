import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/plan_lookup.dart';
import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../http/pagination.dart';
import '../middleware/rate_limiter.dart';
import '../services/api_access_guard.dart';
import '../services/api_key_service.dart';
import '../services/webhook_dispatcher.dart';
import '../services/webhook_service.dart';

/// L'en-tête qui porte la clé d'API reste exporté par ici.
///
/// Il appartient désormais à l'API publique, qui le porte sur ses routes :
/// le baril du package expose les webhooks, et l'en-tête fait partie de
/// leur contrat.
export 'public_api_routes.dart' show apiKeyHeader;

/// Le nombre maximal de caractères du nom d'une clé d'API.
const int maxApiKeyNameLength = 120;

/// Enregistre les routes des clés d'API et des webhooks sortants.
///
/// Les routes `/v1/api-keys` et `/v1/webhooks` décrivent le cycle de vie des
/// identifiants d'intégration : elles s'adressent à l'auteur connecté et
/// sont réservées à la formule Studio (D-15), la seule qui ouvre l'API.
///
/// Les routes `/v1/api` sont l'API publique elle-même : elles s'authentifient
/// par la clé d'API portée par l'en-tête `X-Limpid-Api-Key`. Elles vivent
/// dans `public_api_routes.dart`, pour que l'API publique ne soit pas
/// partagée entre les webhooks et l'API. Le point de composition doit les
/// exempter du jeton de session — le préfixe `/v1/api/` passe alors devant
/// l'authentification par jeton.
///
/// [planOf] lit la formule du compte. Sans cette lecture, aucun compte
/// n'est tenu d'avoir accès à l'API : le service refuse par défaut.
///
/// [audit] reçoit la trace des actions sensibles : création d'une clé,
/// rotation, révocation, enregistrement d'un point de rappel. Sans journal,
/// ces actions sont refusées plutôt que faites sans trace (D-19).
///
/// [dispatcher] envoie les livraisons sortantes. Il est partagé avec les
/// modules qui publient un événement : publication d'un projet, fin d'un
/// export, changement de formule.
void registerWebhookRoutes(
  Router router,
  WebhookDatabase database,
  AppConfig config, {
  PlanLookup? planOf,
  AuditLog? audit,
  WebhookDispatcher? dispatcher,
}) {
  final ApiKeyService keys = ApiKeyService(database: database);
  final WebhookService webhooks = WebhookService(database: database);
  final ApiAccessGuard guard = ApiAccessGuard(planOf: planOf ?? _noPlan);
  final WebhookDispatcher sender =
      dispatcher ?? WebhookDispatcher(database: database, guard: guard);
  final bool allowInsecure = config.profile == LimpidProfile.dev;

  // -------------------------------------------------------------------
  // Les clés d'API.
  // -------------------------------------------------------------------

  router.post('/v1/api-keys', (Request request) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String name = body.requireString(
      'name',
      maxLength: maxApiKeyNameLength,
    );
    final Set<ApiKeyScope> scopes = _readScopes(body);

    final CreatedApiKey created = await keys.create(
      userId: auth.userId,
      name: name,
      scopes: scopes,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'api_key.created',
      targetType: 'api_key',
      targetId: created.record.id,
      metadata: <String, Object?>{
        'name': created.record.name,
        'scopes': created.record.scopes.toList(growable: false)..sort(),
      },
    );
    return ApiResponse.ok(<String, Object?>{
      ...created.record.toJson(),
      'secret': created.secret,
    }, status: HttpStatus.created);
  });

  router.get('/v1/api-keys', (Request request) async {
    final AuthContext auth = await _caller(request, guard);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final WebhookPage<ApiKeyRecord> result = await keys.list(
      userId: auth.userId,
      limit: page.limit,
      cursor: page.cursor,
    );
    return ApiResponse.paginated(
      items: result.items
          .map((ApiKeyRecord record) => record.toJson())
          .toList(growable: false),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  router.get('/v1/api-keys/<keyId>', (Request request, String keyId) async {
    final AuthContext auth = await _caller(request, guard);
    final ApiKeyRecord record = await keys.find(
      userId: auth.userId,
      keyId: keyId,
    );
    return ApiResponse.ok(record.toJson());
  });

  router.post('/v1/api-keys/<keyId>/rotate', (
    Request request,
    String keyId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final CreatedApiKey rotated = await keys.rotate(
      userId: auth.userId,
      keyId: keyId,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'api_key.rotated',
      targetType: 'api_key',
      targetId: rotated.record.id,
      metadata: <String, Object?>{'name': rotated.record.name},
    );
    return ApiResponse.ok(<String, Object?>{
      ...rotated.record.toJson(),
      'secret': rotated.secret,
    });
  });

  router.delete('/v1/api-keys/<keyId>', (Request request, String keyId) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final ApiKeyRecord revoked = await keys.revoke(
      userId: auth.userId,
      keyId: keyId,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'api_key.revoked',
      targetType: 'api_key',
      targetId: revoked.id,
      metadata: <String, Object?>{'name': revoked.name},
    );
    return ApiResponse.ok(revoked.toJson());
  });

  // -------------------------------------------------------------------
  // Le catalogue des evenements.
  // -------------------------------------------------------------------

  // Le catalogue est lisible par le **session** : c'est l'application qui
  // l'affiche quand l'auteur choisit les evenements d'un point de
  // reception. La copie de l'API publique (`/v1/api/events`) exige une
  // cle d'API : elle s'adresse aux programmes, pas a l'auteur.
  router.get('/v1/webhooks/events', (Request request) async {
    await _caller(request, guard);
    return ApiResponse.ok(<Object?>[
      for (final WebhookEvent event in WebhookEvent.values)
        <String, Object?>{'key': event.key, 'label': event.label},
    ]);
  });

  // -------------------------------------------------------------------
  // Les points de rappel.
  // -------------------------------------------------------------------

  router.get('/v1/webhooks/endpoints', (Request request) async {
    final AuthContext auth = await _caller(request, guard);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final WebhookPage<WebhookEndpointRecord> result = await webhooks
        .listEndpoints(
          userId: auth.userId,
          limit: page.limit,
          cursor: page.cursor,
        );
    return ApiResponse.paginated(
      items: result.items
          .map((WebhookEndpointRecord endpoint) => endpoint.toJson())
          .toList(growable: false),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  router.post('/v1/webhooks/endpoints', (Request request) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String url = body.requireString('url', maxLength: 4096);
    final Set<WebhookEvent> events = _readEvents(body);

    final WebhookEndpointRecord endpoint = await webhooks.createEndpoint(
      userId: auth.userId,
      url: url,
      events: events,
      allowInsecure: allowInsecure,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'webhook.endpoint.created',
      targetType: 'webhook_endpoint',
      targetId: endpoint.id,
      metadata: <String, Object?>{
        'url': endpoint.url,
        'events': endpoint.events.toList(growable: false)..sort(),
      },
    );
    return ApiResponse.ok(<String, Object?>{
      ...endpoint.toJson(),
      'secret': endpoint.secret,
    }, status: HttpStatus.created);
  });

  router.get('/v1/webhooks/endpoints/<endpointId>', (
    Request request,
    String endpointId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final WebhookEndpointRecord endpoint = await webhooks.endpointOf(
      userId: auth.userId,
      endpointId: endpointId,
    );
    return ApiResponse.ok(endpoint.toJson());
  });

  router.patch('/v1/webhooks/endpoints/<endpointId>', (
    Request request,
    String endpointId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String? url = body.optionalString('url', maxLength: 4096);
    final Set<WebhookEvent>? events = body.has('events')
        ? _readEvents(body)
        : null;

    final WebhookEndpointRecord endpoint = await webhooks.updateEndpoint(
      userId: auth.userId,
      endpointId: endpointId,
      url: url,
      events: events,
      allowInsecure: allowInsecure,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'webhook.endpoint.updated',
      targetType: 'webhook_endpoint',
      targetId: endpoint.id,
      metadata: <String, Object?>{
        'url': endpoint.url,
        'events': endpoint.events.toList(growable: false)..sort(),
      },
    );
    return ApiResponse.ok(endpoint.toJson());
  });

  router.post('/v1/webhooks/endpoints/<endpointId>/rotate-secret', (
    Request request,
    String endpointId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final RotatedWebhookSecret rotated = await webhooks.rotateSecret(
      userId: auth.userId,
      endpointId: endpointId,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'webhook.endpoint.secret_rotated',
      targetType: 'webhook_endpoint',
      targetId: rotated.endpoint.id,
      metadata: <String, Object?>{
        'previous_secret_expires_at': rotated.previousSecretExpiresAt
            ?.toUtc()
            .toIso8601String(),
      },
    );
    return ApiResponse.ok(<String, Object?>{
      ...rotated.endpoint.toJson(),
      'secret': rotated.secret,
    });
  });

  router.delete('/v1/webhooks/endpoints/<endpointId>', (
    Request request,
    String endpointId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    await webhooks.deleteEndpoint(userId: auth.userId, endpointId: endpointId);
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'webhook.endpoint.deleted',
      targetType: 'webhook_endpoint',
      targetId: endpointId,
    );
    return ApiResponse.ok(<String, Object?>{'id': endpointId, 'deleted': true});
  });

  // -------------------------------------------------------------------
  // Le journal des livraisons.
  // -------------------------------------------------------------------

  router.get('/v1/webhooks/deliveries', (Request request) async {
    final AuthContext auth = await _caller(request, guard);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final WebhookPage<WebhookDeliveryRecord> result = await webhooks
        .listDeliveries(
          userId: auth.userId,
          limit: page.limit,
          cursor: page.cursor,
        );
    return ApiResponse.paginated(
      items: result.items
          .map((WebhookDeliveryRecord delivery) => delivery.toJson())
          .toList(growable: false),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  router.get('/v1/webhooks/deliveries/<deliveryId>', (
    Request request,
    String deliveryId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final WebhookDeliveryRecord delivery = await webhooks.deliveryOf(
      userId: auth.userId,
      deliveryId: deliveryId,
    );
    return ApiResponse.ok(delivery.toJson(includePayload: true));
  });

  router.post('/v1/webhooks/deliveries/<deliveryId>/replay', (
    Request request,
    String deliveryId,
  ) async {
    final AuthContext auth = await _caller(request, guard);
    final AuditLog journal = _requireAudit(audit);
    final WebhookDeliveryRecord delivery = await sender.replay(
      userId: auth.userId,
      deliveryId: deliveryId,
    );
    await _trace(
      request,
      journal,
      userId: auth.userId,
      action: 'webhook.delivery.replayed',
      targetType: 'webhook_delivery',
      targetId: delivery.id,
      metadata: <String, Object?>{
        'endpoint_id': delivery.endpointId,
        'event': delivery.event,
        'status': delivery.status.key,
        'attempts': delivery.attempts,
      },
    );
    return ApiResponse.ok(delivery.toJson(includePayload: true));
  });
}

/// L'appelant autorisé à se servir de l'API.
///
/// La lecture de la formule est faite ici : un compte qui n'est pas sur
/// Studio est refusé avant toute opération.
Future<AuthContext> _caller(Request request, ApiAccessGuard guard) async {
  final AuthContext auth = requireAuthContext(request);
  await guard.requireAccess(auth.userId);
  return auth;
}

/// Trace une action sensible dans le journal d'audit.
///
/// Aucun secret ne figure dans [metadata] : la trace dit ce qui a été
/// fait, jamais le secret qui l'a permis.
Future<void> _trace(
  Request request,
  AuditLog journal, {
  required String userId,
  required String action,
  required String targetType,
  required String targetId,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return journal.record(
    AuditEntry(
      userId: userId,
      action: action,
      targetType: targetType,
      targetId: targetId,
      metadata: metadata,
      ip: clientIpOf(request),
    ),
  );
}

/// Le journal d'audit, ou une erreur qui refuse l'action sensible.
///
/// Une clé d'API et un point de rappel ne sont jamais créés sans trace
/// (D-19) : sans journal, l'action est refusée plutôt que faite sans
/// trace.
AuditLog _requireAudit(AuditLog? audit) {
  if (audit != null) return audit;
  throw const ServiceUnavailableException(
    message:
        "Le journal d'audit n'est pas disponible : la création d'une clé "
        'd\'API et d\'un point de rappel est refusée.',
  );
}

/// Le périmètre demandé par le client, `read` par défaut.
Set<ApiKeyScope> _readScopes(JsonBody body) {
  if (!body.has('scopes')) return <ApiKeyScope>{ApiKeyScope.read};
  final List<dynamic> raw = body.requireList('scopes', maxLength: 8);
  final Set<ApiKeyScope> scopes = <ApiKeyScope>{};
  for (final dynamic value in raw) {
    if (value is! String) {
      throw const ValidationException(
        field: 'scopes',
        message: 'Le champ « scopes » doit porter des noms de périmètre.',
      );
    }
    final ApiKeyScope? scope = ApiKeyScope.parse(value);
    if (scope == null) {
      throw ValidationException(
        field: 'scopes',
        message:
            'Le champ « scopes » doit porter des noms de périmètre parmi '
            '${ApiKeyScope.values.map((ApiKeyScope item) => item.key).join(', ')}.',
      );
    }
    scopes.add(scope);
  }
  if (scopes.isEmpty) {
    throw const ValidationException(
      field: 'scopes',
      message: 'Une clé d\'API doit porter au moins un périmètre.',
    );
  }
  return scopes;
}

/// Les événements auxquels le client s'abonne.
Set<WebhookEvent> _readEvents(JsonBody body) {
  final List<dynamic> raw = body.requireList('events', maxLength: 16);
  final Set<WebhookEvent> events = <WebhookEvent>{};
  for (final dynamic value in raw) {
    if (value is! String) {
      throw const ValidationException(
        field: 'events',
        message: 'Le champ « events » doit porter des noms d\'événement.',
      );
    }
    final WebhookEvent? event = WebhookEvent.parse(value);
    if (event == null) {
      throw ValidationException(
        field: 'events',
        message:
            'Le champ « events » doit porter des noms d\'événement parmi '
            '${WebhookEvent.values.map((WebhookEvent item) => item.key).join(', ')}.',
      );
    }
    events.add(event);
  }
  if (events.isEmpty) {
    throw const ValidationException(
      field: 'events',
      message: 'Un point de rappel doit s\'abonner à au moins un événement.',
    );
  }
  return events;
}

/// La formule d'un compte : aucun compte n'a de formule.
///
/// La lecture par défaut refuse tout le monde : le garde-fou de la formule
/// est fermé tant que le point de composition ne fournit pas la lecture.
Future<String?> _noPlan(String userId) async => null;
