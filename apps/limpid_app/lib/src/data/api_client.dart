import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The default deadline of a request sent to the API.
const Duration defaultApiTimeout = Duration(seconds: 20);

/// The client of the Limpid API.
///
/// The client speaks the real contract of `apps/limpid_api`:
/// - the successful answers are wrapped in `{"data": …}` and the envelope is
///   unwrapped here, once;
/// - the failures are wrapped in `{"error": {"code": …, "message": …}}` and
///   turned into a typed error;
/// - every request carries a deadline and the bearer token when the author
///   is signed in.
///
/// No exception ever escapes the client: a failure is always one of the
/// types of `errors.dart`.
final class ApiClient {
  /// Creates a client.
  ApiClient({
    required this.baseUrl,
    required this.client,
    this.tokenProvider,
    this.requestTimeout = defaultApiTimeout,
    this.closeInjectedClient = false,
  });

  /// The root of the API, for example `https://api.limpid.app`.
  final Uri baseUrl;

  /// The HTTP client used to reach the API.
  ///
  /// It is injected so the tests can replace the network with a fake.
  final http.Client client;

  /// Resolves the bearer token sent with every request.
  ///
  /// The token is resolved for every call: it can expire while the
  /// application runs.
  final AuthTokenProvider? tokenProvider;

  /// The deadline applied to every request.
  final Duration requestTimeout;

  /// Whether [dispose] closes the injected HTTP client.
  final bool closeInjectedClient;

  /// Sends a `GET` request and returns the payload of the envelope.
  Future<Object?> get(String path, {Map<String, String>? query}) async {
    final http.Response response = await _send(
      (Map<String, String> headers) =>
          client.get(_uri(path, query), headers: headers),
    );
    return _payloadOf(response);
  }

  /// Sends a `POST` request and returns the payload of the envelope.
  Future<Object?> post(String path, {Object? body}) async {
    final http.Response response = await _send(
      (Map<String, String> headers) =>
          client.post(_uri(path), headers: headers, body: _encodeBody(body)),
    );
    return _payloadOf(response);
  }

  /// Sends a `PATCH` request and returns the payload of the envelope.
  Future<Object?> patch(String path, {Object? body}) async {
    final http.Response response = await _send(
      (Map<String, String> headers) =>
          client.patch(_uri(path), headers: headers, body: _encodeBody(body)),
    );
    return _payloadOf(response);
  }

  /// Sends a `DELETE` request and returns the payload of the envelope.
  ///
  /// [body] is sent when the route expects one: the deletion of an account
  /// asks for an explicit confirmation.
  Future<Object?> delete(String path, {Object? body}) async {
    final http.Response response = await _send(
      (Map<String, String> headers) =>
          client.delete(_uri(path), headers: headers, body: _encodeBody(body)),
    );
    return _payloadOf(response);
  }

  /// Sends a `POST` request and returns the whole answer.
  ///
  /// The export route answers the file itself, without the JSON envelope.
  Future<http.Response> postRaw(String path, {Object? body}) => _send(
    (Map<String, String> headers) =>
        client.post(_uri(path), headers: headers, body: _encodeBody(body)),
  );

  /// Sends a `POST` request and returns the stream of the answer.
  ///
  /// The AI routes answer with server sent events: the stream is the
  /// interface, the client must not wait for the whole answer.
  Future<http.StreamedResponse> postStream(String path, {Object? body}) async {
    final Map<String, String> headers = await _headers();
    final http.Request request = http.Request('POST', _uri(path))
      ..headers.addAll(headers);
    final String? payload = _encodeBody(body);
    if (payload != null) request.body = payload;
    try {
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorForStatus(
          response.statusCode,
          await response.stream.bytesToString(),
        );
      }
      return response;
    } on TimeoutException catch (error) {
      throw ApiTimeoutException(
        'The API did not answer before the timeout.',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ApiNetworkException(
        'The API is unreachable: ${error.message}',
        cause: error,
      );
    }
  }

  /// Releases the resources held by the client.
  void dispose() {
    if (closeInjectedClient) client.close();
  }

  /// Sends a request and turns the failures into typed errors.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final Map<String, String> headers = await _headers();
    try {
      final http.Response response = await request(
        headers,
      ).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorForStatus(response.statusCode, response.body);
      }
      return response;
    } on TimeoutException catch (error) {
      throw ApiTimeoutException(
        'The API did not answer before the timeout.',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ApiNetworkException(
        'The API is unreachable: ${error.message}',
        cause: error,
      );
    }
  }

  /// Builds the typed error matching an unsuccessful answer.
  ApiException _errorForStatus(int status, String body) {
    final ({String code, String message})? error = _decodeError(body);
    final String message = error?.message ?? 'The API answered $status.';
    final String? code = error?.code;
    if (status == 401 || status == 403) {
      return ApiUnauthorizedException(message, code: code, statusCode: status);
    }
    if (status == 404) {
      return ApiNotFoundException(message, code: code, statusCode: status);
    }
    if (status >= 400 && status < 500) {
      return ApiValidationException(message, code: code, statusCode: status);
    }
    return ApiServerException(message, code: code, statusCode: status);
  }

  /// Reads the `error` envelope of an unsuccessful answer.
  ({String code, String message})? _decodeError(String body) {
    final Object? decoded = _decodeJson(body);
    if (decoded is! Map<String, Object?>) return null;
    final Object? error = decoded['error'];
    if (error is! Map<String, Object?>) return null;
    final Object? code = error['code'];
    final Object? message = error['message'];
    return (
      code: code is String ? code : 'api_error',
      message: message is String ? message : 'The request failed.',
    );
  }

  /// Reads the payload of the envelope of a successful answer.
  Object? _payloadOf(http.Response response) {
    final Object? decoded = _decodeJson(response.body);
    if (decoded is! Map<String, Object?>) {
      throw ApiMalformedResponseException(
        'The API did not return a JSON object.',
        statusCode: response.statusCode,
      );
    }
    if (!decoded.containsKey('data')) {
      throw ApiMalformedResponseException(
        'The API did not return the expected envelope.',
        statusCode: response.statusCode,
      );
    }
    return decoded['data'];
  }

  /// Decodes a JSON body.
  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException catch (error) {
      throw ApiMalformedResponseException(
        'The API did not return valid JSON.',
        cause: error,
      );
    }
  }

  /// Encodes the body of a request.
  String? _encodeBody(Object? body) {
    if (body == null) return null;
    return jsonEncode(body);
  }

  /// Builds the headers of a request.
  Future<Map<String, String>> _headers() async {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    final String? token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Builds the URI of a route of the API.
  Uri _uri(String path, [Map<String, String>? query]) {
    final String base = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    final String route = path.startsWith('/') ? path : '/$path';
    return baseUrl.replace(path: '$base$route', queryParameters: query);
  }
}
