import 'dart:io';

import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../dependencies.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../http/pagination.dart';
import '../middleware/rate_limiter.dart';
import '../services/access_control.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';

/// The maximum length of the title of a project.
const int maxProjectTitleLength = 200;

/// The maximum length of the synopsis of a project.
const int maxProjectSynopsisLength = 4000;

/// Registers the routes of the projects.
void registerProjectRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  router.get('/v1/projects', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );

    final ProjectPage result = await dependencies.projects.list(
      userId: auth.userId,
      limit: page.limit,
      cursor: page.cursor,
    );

    return ApiResponse.paginated(
      items: result.items.map((ProjectRecord item) => item.toJson()).toList(),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  router.post('/v1/projects', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final String title = body.requireString(
      'title',
      maxLength: maxProjectTitleLength,
    );
    final String synopsis =
        body.optionalString('synopsis', maxLength: maxProjectSynopsisLength) ??
        '';
    final String language = body.optionalString('language') ?? 'fr-FR';
    final ManuscriptStatus status = body.has('status')
        ? body.requireEnum('status', ManuscriptStatus.values)
        : ManuscriptStatus.draft;

    // Le nombre de projets est une jauge de la formule : la limite est
    // verifiee avant la creation, pour que le compte ne depasse jamais son
    // contrat.
    if (quota != null) {
      final ProjectPage page = await dependencies.projects.list(
        userId: auth.userId,
        limit: 1,
        cursor: null,
      );
      await quota.ensureGauge(
        userId: auth.userId,
        feature: QuotaFeature.projects,
        current: page.total,
      );
    }

    final ProjectRecord project = await dependencies.projects.create(
      ownerId: auth.userId,
      title: title,
      synopsis: synopsis,
      status: status,
      language: language,
      orderKey: OrderKey.initial.value,
    );

    return ApiResponse.ok(project.toJson(), status: HttpStatus.created);
  });

  router.get('/v1/projects/<projectId>', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final ProjectAccess access = await AccessControl.requireProject(
      dependencies.projects,
      projectId,
      auth,
    );
    return ApiResponse.ok(access.project.toJson());
  });

  router.patch('/v1/projects/<projectId>', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final ProjectAccess access = await AccessControl.requireEditor(
      dependencies.projects,
      projectId,
      auth,
    );
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final ProjectRecord updated = access.project.copyWith(
      title: body.optionalString('title', maxLength: maxProjectTitleLength),
      synopsis: body.optionalString(
        'synopsis',
        maxLength: maxProjectSynopsisLength,
      ),
      status: body.has('status')
          ? body.requireEnum('status', ManuscriptStatus.values)
          : null,
      language: body.optionalString('language'),
      isPublic: body.optionalBool('is_public'),
    );

    final ProjectRecord stored = await dependencies.projects.update(updated);
    return ApiResponse.ok(stored.toJson());
  });

  router.delete('/v1/projects/<projectId>', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final ProjectAccess access = await AccessControl.requireEditor(
      dependencies.projects,
      projectId,
      auth,
    );

    await dependencies.projects.softDelete(projectId: projectId);
    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: 'project.deleted',
        targetType: 'project',
        targetId: projectId,
        metadata: <String, Object?>{'title': access.project.title},
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(<String, Object?>{'id': projectId, 'deleted': true});
  });
}
