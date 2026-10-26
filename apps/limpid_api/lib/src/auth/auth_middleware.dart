import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';
import 'auth_context.dart';
import 'jwt_verifier.dart';
import 'two_factor_guard.dart';

export 'auth_context.dart';
export 'two_factor_guard.dart';

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
      final AuthContext context = await _authenticate(request, verifier);
      return innerHandler(
        request.change(context: <String, Object>{authContextKey: context}),
      );
    };
  };
}

/// Reads the token of [request] and returns the caller it identifies.
///
/// Throws an [UnauthorizedException] when the request carries no usable
/// token.
Future<AuthContext> _authenticate(Request request, JwtVerifier verifier) async {
  final String? token = bearerToken(request);
  if (token == null) {
    throw const UnauthorizedException(
      message:
          'Une authentification est requise pour accéder à cette '
          'ressource.',
      details: <String, Object?>{'reason': 'missing_token'},
    );
  }
  return verifier.verify(token);
}

/// The routes that answer without a token.
const Set<String> publicPaths = <String>{'/health', '/ready', '/v1/sync'};

/// The prefixes of the routes that answer without a token.
///
/// The showcase of the published books is public : a reader has no account.
/// The route carries the identifier of the book, so it is matched by its
/// prefix and not by an exact path.
const List<String> publicPathPrefixes = <String>['/v1/public/'];

/// The prefixes of the routes that answer without a proof of the second
/// factor.
///
/// The routes of the double authentication are the ones that let the caller
/// activate it and prove it : they must stay reachable when the account
/// cannot use the rest of the API.
const List<String> defaultTwoFactorExemptPrefixes = <String>['/v1/me/2fa'];

/// Builds the middleware authenticating the calls of the protected routes.
///
/// The routes of [exemptPaths] and of [exemptPrefixes] answer without a
/// token: the health probes are public, the showcase of the published books
/// is read by readers who have no account, and the real time relay carries
/// its token in the query string, because a browser cannot set headers on a
/// WebSocket handshake.
///
/// When [twoFactorGuard] is given, the second factor is checked right
/// after the token: an account whose plan requires the double
/// authentication and which has not activated it is refused with a
/// `ForbiddenException`, and an account which has activated it must carry
/// the proof of the second factor in the `X-Limpid-2FA` header. The routes
/// of [twoFactorExemptPrefixes] are exempt from that second check.
Middleware authenticationMiddleware({
  required JwtVerifier verifier,
  Set<String> exemptPaths = publicPaths,
  List<String> exemptPrefixes = publicPathPrefixes,
  TwoFactorGuard? twoFactorGuard,
  List<String> twoFactorExemptPrefixes = defaultTwoFactorExemptPrefixes,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final String path = request.requestedUri.path;
      if (exemptPaths.contains(path) ||
          exemptPrefixes.any((String prefix) => path.startsWith(prefix))) {
        return innerHandler(request);
      }
      final AuthContext context = await _authenticate(request, verifier);
      if (twoFactorGuard != null &&
          !twoFactorExemptPrefixes.any(
            (String prefix) => path.startsWith(prefix),
          )) {
        await twoFactorGuard.verifySecondFactor(context, request);
      }
      return innerHandler(
        request.change(context: <String, Object>{authContextKey: context}),
      );
    };
  };
}
