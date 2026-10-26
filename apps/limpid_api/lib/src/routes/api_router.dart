import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/admin_database.dart';
import '../db/quota_database.dart';
import '../db/team_database.dart';
import '../db/two_factor_database.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../services/quota_service.dart';
import 'account_routes.dart';
import 'admin_routes.dart';
import 'ai_routes.dart';
import 'checkout_routes.dart';
import 'comment_routes.dart';
import 'export_routes.dart';
import 'health_routes.dart';
import 'project_routes.dart';
import 'publication_routes.dart';
import 'quota_routes.dart';
import 'sync_routes.dart';
import 'sync_socket_routes.dart';
import 'team_routes.dart';
import 'two_factor_routes.dart';

/// Builds the router of the API.
///
/// Every route of the contract is registered here; the authentication, the
/// CORS, the timeout and the rate limit are applied by the server, around
/// this router.
Router buildRouter(AppDependencies dependencies, AppConfig config) {
  final Router router = Router(notFoundHandler: _notFound);

  // Le service de quota porte le garde-fou des exports et des appels au
  // modèle. Il n'existe que si la base des formules est câblée.
  final QuotaDatabase? quotaDatabase = dependencies.quotas;
  final QuotaService? quota = quotaDatabase == null
      ? null
      : QuotaService(database: quotaDatabase);

  registerHealthRoutes(router, dependencies);
  registerProjectRoutes(router, dependencies, config, quota: quota);
  registerSyncRoutes(router, dependencies, config, quota: quota);
  registerAiRoutes(router, dependencies, config, quota: quota);
  registerExportRoutes(router, dependencies, config, quota: quota);
  registerCheckoutRoutes(router, dependencies, config);
  registerAccountRoutes(router, dependencies, config);
  registerCommentRoutes(
    router,
    dependencies,
    config,
    comments: dependencies.comments,
  );
  registerPublicationRoutes(router, dependencies, config);
  registerSyncSocketRoute(router, dependencies, config);

  // Les quatre services du lot 7 sont optionnels : un serveur qui ne les
  // câble pas ne sert pas leurs routes, plutôt que de les servir en
  // erreur.
  if (quotaDatabase != null) {
    registerQuotaRoutes(
      router,
      quotaDatabase,
      config,
      audit: dependencies.audit,
    );
  }
  final TwoFactorDatabase? twoFactor = dependencies.twoFactor;
  if (twoFactor != null) {
    registerTwoFactorRoutes(
      router,
      twoFactor,
      config,
      planOf: dependencies.planOf,
    );
  }
  final TeamDatabase? teams = dependencies.teams;
  if (teams != null) {
    registerTeamRoutes(router, teams, config);
  }
  final AdminDatabase? admin = dependencies.admin;
  if (admin != null) {
    registerAdminRoutes(router, admin, config, quota: quota);
  }

  return router;
}

Response _notFound(Request request) {
  return ApiResponse.error(
    const NotFoundException(
      message: "Cette route n'existe pas.",
      details: <String, Object?>{'path': 'unknown'},
    ),
  );
}
