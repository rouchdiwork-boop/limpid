import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The HTTP client of the synchronisation.
///
/// The client knows the address of the API, the bearer token and the timeout
/// of the requests, and it turns the failures of the API into the typed
/// errors of `limpid_sync`: a timeout, an unreachable API, a session that
/// expired.
///
/// The class is shared by the transport of the operations and by the
/// registry of the projects: the two address the same API with the same
/// credentials, and they must fail the same way — a failure of the
/// registration must look like a failure of the push.
final class SyncApiClient {
  /// Creates a client.
  const SyncApiClient({
    required this.baseUrl,
    required this.client,
    this.tokenProvider,
    this.twoFactorProof,
    this.requestTimeout = defaultRequestTimeout,
  });

  /// The root of the API, for example `https://api.limpid.app`.
  final Uri baseUrl;

  /// The HTTP client used to reach the API.
  final http.Client client;

  /// Resolves the bearer token sent with every request.
  final AuthTokenProvider? tokenProvider;

  /// Resolves the proof of the second factor sent with every request.
  ///
  /// The synchronisation reaches the same routes as the rest of the
  /// application: the server refuses them when the proof is missing. The
  /// proof is resolved for every call, like the token.
  final String? Function()? twoFactorProof;

  /// The timeout applied to every request.
  final Duration requestTimeout;

  /// Sends a request and turns the failures into typed errors.
  ///
  /// The errors are never swallowed: the caller — the synchronisation
  /// client of `limpid_sync` — decides what an offline device does with
  /// them, and the operations stay in the durable queue until the API
  /// answers.
  Future<http.Response> send(Future<http.Response> Function() request) async {
    try {
      final http.Response response = await request().timeout(requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw _errorFor(response);
    } on TimeoutException catch (error) {
      throw SyncTransportException(
        'The API did not answer before the timeout.',
        code: 'sync_timeout',
        isNetworkFailure: true,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw SyncTransportException(
        'The API is unreachable: ${error.message}',
        code: 'sync_unreachable',
        isNetworkFailure: true,
        cause: error,
      );
    }
  }

  /// Sends a request and answers `null` when the API answers `404`.
  ///
  /// The absence of a resource is an answer, not a failure: the registry of
  /// the projects asks the server whether it knows a project, and a `404`
  /// means "create it". Every other failure is raised.
  Future<http.Response?> sendOptional(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await send(request);
    } on SyncTransportException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The headers of a request.
  ///
  /// The token is resolved for every request: the session rotates it, and a
  /// request sent with a stale token would be refused. The proof of the
  /// second factor is resolved the same way: it expires, and the author then
  /// proves the second factor again.
  Future<Map<String, String>> headers() async {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    final String? token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final String? proof = twoFactorProof?.call();
    if (proof != null && proof.isNotEmpty) {
      headers[twoFactorProofHeader] = proof;
    }
    return headers;
  }

  /// Builds the URI of the path [path] of the API.
  ///
  /// [path] is the path of the API, already escaped by the caller: an
  /// identifier that holds a `/` would otherwise address another route.
  Uri uri(String path, {Map<String, String>? query}) {
    final String root = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$root$path', queryParameters: query);
  }

  /// Decodes the body of a response and unwraps the envelope of the API.
  ///
  /// The envelope of the API is a convention of the repository: the `data`
  /// field carries the answer, and the clients of the repository are the
  /// only place that knows it.
  Object? decodeEnvelope(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    } on FormatException catch (error) {
      throw SyncTransportException(
        'The server did not return valid JSON.',
        code: 'sync_invalid_payload',
        cause: error,
      );
    }
  }

  /// Decodes the body of a response as an object.
  Map<String, Object?> decodeObject(String body) {
    final Object? decoded = decodeEnvelope(body);
    if (decoded is! Map<String, Object?>) {
      throw const SyncTransportException(
        'The server did not return a JSON object.',
        code: 'sync_invalid_payload',
      );
    }
    return decoded;
  }

  /// Builds the typed error matching an unsuccessful response.
  ///
  /// A refusal of the credentials becomes an [ApiUnauthorizedException]: the
  /// application recognises it, and asks the author for the code of the
  /// second factor when the refusal is about the proof. The other failures
  /// stay the errors of `limpid_sync`: the operations wait in the queue.
  Object _errorFor(http.Response response) {
    final ({String code, String message})? error = _decodeError(response.body);
    final String message =
        error?.message ?? 'The API answered ${response.statusCode}.';
    final String? code = error?.code;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return ApiUnauthorizedException(
        message,
        code: code ?? 'sync_unauthorized',
        statusCode: response.statusCode,
      );
    }
    return SyncTransportException(
      message,
      code: code ?? 'sync_http_error',
      statusCode: response.statusCode,
    );
  }

  /// Reads the `error` envelope of an unsuccessful response.
  ({String code, String message})? _decodeError(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return null;
      final Object? error = decoded['error'];
      if (error is! Map<String, Object?>) return null;
      final Object? code = error['code'];
      final Object? message = error['message'];
      return (
        code: code is String ? code : 'sync_http_error',
        message: message is String ? message : 'The request failed.',
      );
    } on FormatException {
      return null;
    }
  }
}
