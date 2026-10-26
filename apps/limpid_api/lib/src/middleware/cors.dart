import 'dart:io';

import 'package:shelf/shelf.dart';

/// The methods allowed by the preflight requests.
const List<String> _allowedMethods = <String>[
  'GET',
  'POST',
  'PATCH',
  'DELETE',
  'OPTIONS',
];

/// The headers allowed by the preflight requests.
const List<String> _allowedHeaders = <String>[
  'authorization',
  'content-type',
  'idempotency-key',
  'x-request-id',
];

/// Builds the middleware answering the cross origin requests.
///
/// Only the origins of the white list receive the `Access-Control-Allow-
/// Origin` header; the others are simply not allowed by the browser.
Middleware corsMiddleware({required List<String> allowedOrigins}) {
  final Set<String> whitelist = allowedOrigins.toSet();
  return (Handler innerHandler) {
    return (Request request) async {
      final String? origin = request.headers['origin'];
      final bool isAllowed = origin != null && whitelist.contains(origin);

      if (request.method == 'OPTIONS') {
        final Map<String, String> headers = <String, String>{
          'access-control-allow-methods': _allowedMethods.join(', '),
          'access-control-allow-headers': _allowedHeaders.join(', '),
          'access-control-max-age': '600',
          'vary': 'Origin',
        };
        if (isAllowed) {
          headers['access-control-allow-origin'] = origin;
          headers['access-control-allow-credentials'] = 'true';
        }
        return Response(HttpStatus.noContent, headers: headers);
      }

      final Response response = await innerHandler(request);
      if (!isAllowed) return response;

      return response.change(
        headers: <String, String>{
          ...response.headers,
          'access-control-allow-origin': origin,
          'access-control-allow-credentials': 'true',
          'vary': 'Origin',
        },
      );
    };
  };
}
