import 'dart:async';

import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../logging/logger.dart';

/// Builds the middleware converting any failure into a safe HTTP response.
///
/// Application errors keep their stable code and their French message;
/// unexpected errors are logged with their context and answered with the
/// generic `internal_error` code, never with a stack trace.
Middleware errorHandlerMiddleware({
  required Logger logger,
  Duration timeout = const Duration(seconds: 30),
  String Function(Request request)? requestIdOf,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on AppException catch (error) {
        logger.warning('request.failed', <String, Object?>{
          'code': error.code,
          'status': error.statusCode,
          'method': request.method,
          'path': request.requestedUri.path,
          if (requestIdOf != null) 'request_id': requestIdOf(request),
        });
        return ApiResponse.error(error);
      } on TimeoutException {
        logger.error('request.timeout', <String, Object?>{
          'method': request.method,
          'path': request.requestedUri.path,
          if (requestIdOf != null) 'request_id': requestIdOf(request),
        });
        return ApiResponse.error(
          RequestTimeoutException(
            message: 'La requête a dépassé le temps de traitement autorisé.',
            timeoutSeconds: timeout.inSeconds,
          ),
        );
      } on HijackException {
        // The real time relay hijacks the connection to speak WebSocket:
        // the exception unwinds the middleware stack and must not be caught.
        rethrow;
      } on Object catch (error, stackTrace) {
        logger.error('request.unexpected_error', <String, Object?>{
          'error': error.runtimeType.toString(),
          'method': request.method,
          'path': request.requestedUri.path,
          if (requestIdOf != null) 'request_id': requestIdOf(request),
          'stack': stackTrace.toString(),
        });
        return ApiResponse.error(
          const InternalException(
            message:
                'Une erreur interne est survenue. Réessayez dans un instant.',
          ),
        );
      }
    };
  };
}
