import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';
import 'auth_context.dart';
import 'jwt_verifier.dart';

export 'auth_context.dart';

/// The key under which the [AuthContext] is stored in the request context.
const String authContextKey = 'limpid.auth';

/// Extracts the bearer token of a request.
///
/// Returns `null` when the header is absent or does not carry a token.
String? bearerToken(Request request) {
  final String? header = request.headers['authorization'];
  if (header == null) return null;
  final String trimmed = header.trim();
  if (trimmed.length <= 7) return null;
  if (trimmed.substring(0, 7).toLowerCase() != 'bearer ') return null;
  final String token = trimmed.substring(7).trim();
  if (token.isEmpty) return null;
  return token;
}

/// Returns the authenticated caller of a request, `null` when anonymous.
AuthContext? authOf(Request request) {
  final Object? context = request.context[authContextKey];
  return context is AuthContext ? context : null;
}

/// Returns the authenticated caller of a request.
///
/// Throws an [UnauthorizedException] when the request is anonymous.
AuthContext requireAuthContext(Request request) {
  final AuthContext? auth = authOf(request);
  if (auth == null) {
    throw const UnauthorizedException();
  }
  return auth;
}

/// Builds the middleware enforcing the presence of a valid token.
Middleware requireAuth(JwtVerifier verifier) {
  return (Handler innerHandler) {
    return (Request request) async {
      final String? token = bearerToken(request);
      if (token == null) {
        throw const UnauthorizedException(
          message:
              'Une authentification est requise pour accéder à cette '
              'ressource.',
          details: <String, Object?>{'reason': 'missing_token'},
        );
      }
      final AuthContext context = await verifier.verify(token);
      return innerHandler(
        request.change(context: <String, Object>{authContextKey: context}),
      );
    };
  };
}

/// The routes that answer without a token.
const Set<String> publicPaths = <String>{'/health', '/ready', '/v1/sync'};

/// The prefixes of the routes that answer without a token.
///
/// The showcase of the published books is public : a reader has no account.
/// The route carries the identifier of the book, so it is matched by its
/// prefix and not by an exact path.
const List<String> publicPathPrefixes = <String>['/v1/public/'];

/// Builds the middleware authenticating the calls of the protected routes.
///
/// The routes of [exemptPaths] and of [exemptPrefixes] answer without a
/// token: the health probes are public, the showcase of the published books
/// is read by readers who have no account, and the real time relay carries
/// its token in the query string, because a browser cannot set headers on a
/// WebSocket handshake.
Middleware authenticationMiddleware({
  required JwtVerifier verifier,
  Set<String> exemptPaths = publicPaths,
  List<String> exemptPrefixes = publicPathPrefixes,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final String path = request.requestedUri.path;
      if (exemptPaths.contains(path) ||
          exemptPrefixes.any((String prefix) => path.startsWith(prefix))) {
        return innerHandler(request);
      }
      return requireAuth(verifier)(innerHandler)(request);
    };
  };
}
