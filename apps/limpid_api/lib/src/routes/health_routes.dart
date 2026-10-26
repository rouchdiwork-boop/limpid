import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';

/// Registers the public health routes.
void registerHealthRoutes(Router router, AppDependencies dependencies) {
  router.get('/health', (Request request) {
    return ApiResponse.ok(<String, Object?>{
      'status': 'ok',
      'service': 'limpid-api',
    });
  });

  router.get('/ready', (Request request) async {
    final bool database = await dependencies.databaseProbe.ping();
    final bool redis = await _pingKeyValue(dependencies);
    final bool isReady = database && redis;

    if (!isReady) {
      throw ServiceUnavailableException(
        message: 'Le service n\'est pas encore prêt à répondre.',
        details: <String, Object?>{'database': database, 'redis': redis},
      );
    }

    return ApiResponse.ok(<String, Object?>{
      'status': 'ready',
      'database': database,
      'redis': redis,
    });
  });
}

Future<bool> _pingKeyValue(AppDependencies dependencies) async {
  try {
    return await dependencies.keyValue.ping();
  } on Object {
    return false;
  }
}
