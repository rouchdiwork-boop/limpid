import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import 'account_routes.dart';
import 'ai_routes.dart';
import 'checkout_routes.dart';
import 'comment_routes.dart';
import 'export_routes.dart';
import 'health_routes.dart';
import 'project_routes.dart';
import 'publication_routes.dart';
import 'sync_routes.dart';
import 'sync_socket_routes.dart';

/// Builds the router of the API.
///
/// Every route of the contract is registered here; the authentication, the
/// CORS, the timeout and the rate limit are applied by the server, around
/// this router.
Router buildRouter(AppDependencies dependencies, AppConfig config) {
  final Router router = Router(notFoundHandler: _notFound);

  registerHealthRoutes(router, dependencies);
  registerProjectRoutes(router, dependencies, config);
  registerSyncRoutes(router, dependencies, config);
  registerAiRoutes(router, dependencies, config);
  registerExportRoutes(router, dependencies, config);
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
