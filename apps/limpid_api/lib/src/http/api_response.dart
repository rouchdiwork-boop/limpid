import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';

/// The uniform response envelope of the API.
///
/// - success: `{"data": ...}`;
/// - paginated: `{"data": [...], "meta": {...}}`;
/// - error: `{"error": {"code": "...", "message": "...", "details": {...}}}`.
abstract final class ApiResponse {
  /// Builds a successful response holding [data].
  static Response ok(
    Object? data, {
    int status = HttpStatus.ok,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _json(status, <String, Object?>{'data': data}, headers);
  }

  /// Builds a successful response with no payload.
  static Response noContent({
    Map<String, String> headers = const <String, String>{},
  }) {
    return Response(
      HttpStatus.noContent,
      body: '',
      headers: <String, String>{'content-length': '0', ...headers},
    );
  }

  /// Builds a paginated response.
  static Response paginated({
    required List<Object?> items,
    required int total,
    required int page,
    required int limit,
    required String? nextCursor,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _json(HttpStatus.ok, <String, Object?>{
      'data': items,
      'meta': <String, Object?>{
        'total': total,
        'page': page,
        'limit': limit,
        'next_cursor': nextCursor,
      },
    }, headers);
  }

  /// Builds a response carrying an already encoded JSON body.
  ///
  /// Used to replay the answer of an idempotent call.
  static Response raw(
    String body, {
    int status = HttpStatus.ok,
    Map<String, String> headers = const <String, String>{},
  }) {
    return Response(
      status,
      body: body,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'content-length': body.length.toString(),
        ...headers,
      },
    );
  }

  /// Encodes [payload] as a JSON body.
  static String encode(Object? payload) => jsonEncode(payload);

  /// Builds the response of a failed request.
  ///
  /// The stack trace is never exposed: only the stable code, the French
  /// message and the safe details travel to the client.
  static Response error(
    AppException exception, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final Map<String, Object?> details = exception.details;
    return _json(exception.statusCode, <String, Object?>{
      'error': <String, Object?>{
        'code': exception.code,
        'message': exception.message,
        'details': details,
      },
    }, headers);
  }

  static Response _json(
    int status,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) {
    final String encoded = jsonEncode(body);
    return Response(
      status,
      body: encoded,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'content-length': encoded.length.toString(),
        ...headers,
      },
    );
  }
}
