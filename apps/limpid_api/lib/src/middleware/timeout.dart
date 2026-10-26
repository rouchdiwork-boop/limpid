import 'dart:async';

import 'package:shelf/shelf.dart';

/// Builds the middleware enforcing the time budget of a request.
///
/// A request slower than [timeout] is aborted with a [TimeoutException],
/// which the error handler turns into a `request_timeout` response.
Middleware timeoutMiddleware({required Duration timeout}) {
  return (Handler innerHandler) {
    return (Request request) {
      final Future<Response> pending = Future<Response>.value(
        innerHandler(request),
      );
      return pending.timeout(timeout);
    };
  };
}
