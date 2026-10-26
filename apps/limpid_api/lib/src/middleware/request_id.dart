import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';

/// The key under which the request identifier is stored in the request
/// context.
const String requestIdKey = 'limpid.request_id';

/// The header carrying the request identifier.
const String requestIdHeader = 'X-Request-Id';

/// The identifier of the request being handled.
String requestIdOf(Request request) {
  final Object? value = request.context[requestIdKey];
  return value is String ? value : 'unknown';
}

/// Builds the middleware attaching an identifier to every request.
///
/// The identifier comes from the `X-Request-Id` header when the caller
/// provides one, so a trace can be followed across services; otherwise a
/// fresh ULID is generated.
Middleware requestIdMiddleware({UlidGenerator? generator}) {
  final UlidGenerator ulid = generator ?? UlidGenerator();
  return (Handler innerHandler) {
    return (Request request) async {
      final String incoming =
          request.headers[requestIdHeader.toLowerCase()] ?? '';
      final String requestId = incoming.trim().isEmpty
          ? ulid.generate().value
          : incoming.trim();
      final Response response = await innerHandler(
        request.change(context: <String, Object>{requestIdKey: requestId}),
      );
      return response.change(
        headers: <String, String>{
          ...response.headers,
          requestIdHeader: requestId,
        },
      );
    };
  };
}
