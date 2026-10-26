import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/plan_lookup.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/sync_store.dart';
import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/pagination.dart';
import '../services/api_access_guard.dart';
import '../services/api_key_service.dart';
import '../services/public_api_service.dart';
import '../services/webhook_service.dart';
import '../sync/tree_builder.dart';

/// L'en-tête qui porte la clé d'API.
///
/// C'est le **seul** en-tête qui porte une clé d'API : l'en-tête
/// `Authorization` reste réservé au jeton de session, pour que les deux
/// genres d'identification ne se confondent jamais.
const String apiKeyHeader = 'x-limpid-api-key';

/// Enregistre les routes de l'API publique.
///
/// L'API publique s'authentifie par la clé d'API portée par l'en-tête
/// `X-Limpid-Api-Key` : le jeton de session ne l'ouvre pas. Elle est
/// réservée à la formule Studio (D-15) : un compte qui n'y est pas est
/// refusé, quelle que soit sa clé.
///
/// [planOf] lit la formule du compte. Sans cette lecture, aucun compte
/// n'est tenu d'avoir accès à l'API : le service refuse par défaut.
///
/// La composition doit appeler cette fonction : elle porte les routes
/// `/v1/api/me` et `/v1/api/events`, qui ont quitté les webhooks pour que
/// l'API publique vive dans un seul endroit.
void registerPublicApiRoutes(
  Router router,
  AppConfig config, {
  required ProjectStore projects,
  required SyncStore sync,
  required WebhookDatabase webhooks,
  PlanLookup? planOf,
}) {
  final ApiKeyService keys = ApiKeyService(database: webhooks);
  final ApiAccessGuard guard = ApiAccessGuard(planOf: planOf ?? _noPlan);
  final PublicApiService service = PublicApiService(
    projects: projects,
    sync: sync,
  );

  // -------------------------------------------------------------------
  // La clé et les événements.
  // -------------------------------------------------------------------

  router.get('/v1/api/me', (Request request) async {
    final ApiKeyRecord record = await _requireKey(request, keys, guard);
    return ApiResponse.ok(<String, Object?>{
      ...record.toJson(),
      'user_id': record.userId,
    });
  });

  router.get('/v1/api/events', (Request request) async {
    await _requireKey(request, keys, guard);
    return ApiResponse.ok(<Object?>[
      for (final WebhookEvent event in WebhookEvent.values)
        <String, Object?>{'key': event.key, 'label': event.label},
    ]);
  });

  // -------------------------------------------------------------------
  // Les ressources du compte.
  // -------------------------------------------------------------------

  router.get('/v1/api/projects', (Request request) async {
    final ApiKeyRecord record = await _requireKey(request, keys, guard);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final ProjectPage result = await service.listProjects(
      userId: record.userId,
      limit: page.limit,
      cursor: page.cursor,
    );
    return ApiResponse.paginated(
      items: result.items
          .map((ProjectRecord item) => item.toJson())
          .toList(growable: false),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  router.get('/v1/api/projects/<projectId>', (
    Request request,
    String projectId,
  ) async {
    final ApiKeyRecord record = await _requireKey(request, keys, guard);
    final PublicProject described = await service.describe(
      userId: record.userId,
      projectId: projectId,
    );
    return ApiResponse.ok(<String, Object?>{
      ...described.project.toJson(),
      'chapters': described.chapters
          .map((PublicChapter chapter) => chapter.toJson())
          .toList(growable: false),
    });
  });

  router.get('/v1/api/projects/<projectId>/tree', (
    Request request,
    String projectId,
  ) async {
    final ApiKeyRecord record = await _requireKey(request, keys, guard);
    final List<DocumentTree> trees = await service.tree(
      userId: record.userId,
      projectId: projectId,
    );
    return ApiResponse.ok(
      trees.map((DocumentTree tree) => tree.toJson()).toList(growable: false),
    );
  });
}

/// La clé d'API portée par la requête, ou une erreur.
///
/// La clé doit être active, porter le périmètre de lecture et appartenir à un
/// compte autorisé par la formule : l'ordre des refus ne divulgue rien, il
/// dit seulement ce qui manque à l'appelant.
///
/// Une clé inconnue, falsifiée ou révoquée reçoit exactement le même refus :
/// l'appelant ne peut pas deviner quelles clés existent.
Future<ApiKeyRecord> _requireKey(
  Request request,
  ApiKeyService service,
  ApiAccessGuard guard,
) async {
  final String? presented = request.headers[apiKeyHeader];
  if (presented == null || presented.trim().isEmpty) {
    throw const UnauthorizedException(
      message: 'Une clé d\'API est requise pour accéder à cette ressource.',
      details: <String, Object?>{'reason': 'missing_api_key'},
    );
  }
  final ApiKeyRecord? record = await service.authenticate(presented);
  if (record == null) {
    throw const UnauthorizedException(
      message: 'Cette clé d\'API est inconnue ou révoquée.',
      details: <String, Object?>{'reason': 'unknown_api_key'},
    );
  }
  // La formule ouvre l'API publique (D-15) : un compte qui n'y est pas n'y
  // entre pas, quelle que soit sa clé.
  await guard.requireAccess(record.userId);
  _requireScope(record, ApiKeyScope.read);
  return record;
}

/// Vérifie que la clé [record] porte le périmètre [scope].
void _requireScope(ApiKeyRecord record, ApiKeyScope scope) {
  if (record.scopes.contains(scope.key)) return;
  throw ForbiddenException(
    message: 'Cette clé d\'API ne porte pas le périmètre requis.',
    details: <String, Object?>{'scope': scope.key},
  );
}

/// La formule d'un compte : aucun compte n'a de formule.
///
/// La lecture par défaut refuse tout le monde : le garde-fou de la formule
/// est fermé tant que le point de composition ne fournit pas la lecture.
Future<String?> _noPlan(String userId) async => null;
