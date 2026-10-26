import 'dart:io';

import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../logging/logger.dart';
import 'request_id.dart';

/// Builds the middleware logging the completion of every request.
///
/// The log holds the method, the path, the status, the duration and the
/// identifiers of the request and of the caller. It never holds a body, a
/// book text or a token.
Middleware requestLoggingMiddleware({required Logger logger}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final Stopwatch stopwatch = Stopwatch()..start();
      int status = HttpStatus.internalServerError;
      try {
        final Response response = await innerHandler(request);
        status = response.statusCode;
        return response;
      } finally {
        stopwatch.stop();
        final AuthContext? auth = authOf(request);
        logger.info('request.completed', <String, Object?>{
          'request_id': requestIdOf(request),
          'method': request.method,
          'path': request.requestedUri.path,
          'status': status,
          'duration_ms': stopwatch.elapsedMilliseconds,
          if (auth != null) 'user_id': auth.userId,
        });
      }
    };
  };
}
