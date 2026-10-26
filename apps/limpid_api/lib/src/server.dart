import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'auth/auth_middleware.dart';
import 'config/app_config.dart';
import 'dependencies.dart';
import 'logging/logger.dart';
import 'middleware/cors.dart';
import 'middleware/error_handler.dart';
import 'middleware/rate_limiter.dart';
import 'middleware/request_id.dart';
import 'middleware/request_logging.dart';
import 'middleware/timeout.dart';
import 'production_dependencies.dart';
import 'routes/api_router.dart';

/// Builds the HTTP handler of the API.
///
/// The middlewares are applied from the outside to the inside: the request
/// identifier is attached first so every log carries it, then the request is
/// logged, then the errors are converted, then the cross origin headers, the
/// time budget, the authentication and the rate limit are applied.
Handler buildHandler(AppDependencies dependencies, AppConfig config) {
  final Logger logger = dependencies.logger;
  final TokenBucketRateLimiter aiLimiter = TokenBucketRateLimiter(
    capacity: config.aiRateLimitCapacity,
    refillPerSecond: config.aiRateLimitRefillPerSecond,
  );
  // Le seau général couvre **toutes** les routes de l'API : un export
  // reconstruit un livre entier, un checkout crée une vraie session de
  // paiement, l'export des données personnelles relit tous les documents
  // d'un auteur. Aucune de ces routes ne peut rester sans limite.
  final TokenBucketRateLimiter apiLimiter = TokenBucketRateLimiter(
    capacity: config.apiRateLimitCapacity,
    refillPerSecond: config.apiRateLimitRefillPerSecond,
  );

  return const Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(requestLoggingMiddleware(logger: logger))
      .addMiddleware(
        errorHandlerMiddleware(
          logger: logger,
          timeout: config.requestTimeout,
          requestIdOf: requestIdOf,
        ),
      )
      .addMiddleware(corsMiddleware(allowedOrigins: config.allowedOrigins))
      .addMiddleware(timeoutMiddleware(timeout: config.requestTimeout))
      .addMiddleware(
        authenticationMiddleware(verifier: dependencies.jwtVerifier),
      )
      .addMiddleware(
        rateLimitMiddleware(
          limiter: apiLimiter,
          scope: 'api',
          applies: (Request request) =>
              request.requestedUri.path.startsWith('/v1/'),
          keyOf: callerKeyOf,
        ),
      )
      .addMiddleware(
        rateLimitMiddleware(
          limiter: aiLimiter,
          applies: (Request request) =>
              request.requestedUri.path.startsWith('/v1/ai/'),
        ),
      )
      .addHandler(buildRouter(dependencies, config).call);
}

/// The key of the bucket a call belongs to.
///
/// An authenticated call is keyed by the account: a shared address — un
/// bureau, un réseau d'hôtel — must not exhaust the quota of a single
/// author. An anonymous call is keyed by its address.
String callerKeyOf(Request request) {
  final AuthContext? auth = authOf(request);
  if (auth != null) return 'user:${auth.userId}';
  return 'ip:${clientIpOf(request)}';
}

/// Starts the HTTP server of the API.
///
/// The server listens on the port of [config]; the port `0` asks the
/// operating system for an ephemeral port, which is what the test suite
/// uses. The [dependencies] are injected so the test suite can run the whole
/// stack without any external service.
Future<HttpServer> createServer(
  AppConfig config, {
  AppDependencies? dependencies,
}) async {
  final AppDependencies resolved =
      dependencies ?? await buildProductionDependencies(config);
  final Handler handler = buildHandler(resolved, config);

  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  resolved.logger.info('server.started', <String, Object?>{
    'port': server.port,
    'address': server.address.address,
  });
  return server;
}
