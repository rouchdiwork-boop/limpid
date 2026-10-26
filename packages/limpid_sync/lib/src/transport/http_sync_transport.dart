import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/src/errors.dart';
import 'package:limpid_sync/src/transport/auth_token_provider.dart';
import 'package:limpid_sync/src/transport/op_codec.dart';
import 'package:limpid_sync/src/transport/sync_transport.dart';

/// A [SyncTransport] talking to the Limpid API over REST.
///
/// The transport implements the contract of `docs/PROMPT.md` §7:
/// `POST /v1/projects/:id/ops` pushes operations and
/// `GET /v1/projects/:id/ops?since=` pulls them.
///
/// The [http.Client] is injected so the tests can replace the network with
/// a fake, and the token is resolved for every request so it can expire or
/// be rotated while the application runs.
final class HttpSyncTransport implements SyncTransport {
  /// Creates a REST transport.
  HttpSyncTransport({
    required this.baseUrl,
    required this.client,
    this.tokenProvider,
    this.requestTimeout = defaultRequestTimeout,
    this.closeInjectedClient = false,
  });

  /// The HTTP client used to reach the API.
  ///
  /// It is injected so the tests can replace the network with a fake.
  final http.Client client;

  /// The root of the API, for example `https://api.limpid.app`.
  final Uri baseUrl;

  /// Resolves the bearer token sent with every request.
  final AuthTokenProvider? tokenProvider;

  /// The timeout applied to every request.
  final Duration requestTimeout;

  /// Whether [dispose] closes the injected HTTP client.
  ///
  /// The default is `false`: the client is usually owned by the application,
  /// which may share it with the rest of its API layer.
  final bool closeInjectedClient;

  @override
  Future<PushResult> push(List<SyncOp> ops) async {
    if (ops.isEmpty) return PushResult.empty;
    final byDocument = <String, List<SyncOp>>{};
    for (final op in ops) {
      byDocument.putIfAbsent(op.doc.value, () => <SyncOp>[]).add(op);
    }
    final accepted = <SyncOp>[];
    final duplicated = <SyncOp>[];
    final rejected = <RejectedOperation>[];
    var lamportAck = 0;
    for (final entry in byDocument.entries) {
      final result = await _pushDocument(entry.key, entry.value);
      accepted.addAll(result.accepted);
      duplicated.addAll(result.duplicated);
      rejected.addAll(result.rejected);
      if (result.lamportAck > lamportAck) lamportAck = result.lamportAck;
    }
    return PushResult(
      accepted: List<SyncOp>.unmodifiable(accepted),
      duplicated: List<SyncOp>.unmodifiable(duplicated),
      rejected: List<RejectedOperation>.unmodifiable(rejected),
      lamportAck: lamportAck,
    );
  }

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async {
    final uri = _opsUri(
      docId,
      query: <String, String>{'since': '$since', 'limit': '$limit'},
    );
    final headers = await _headers();
    final response = await _send(() => client.get(uri, headers: headers));
    final Object? payload = _decodeEnvelope(response.body);
    // The API answers `{"data": [ … ]}` for the pull, while a flat
    // `{"operations": [ … ]}` is also accepted : the transport has to serve
    // both shapes.
    final Object? operations = payload is Map<String, Object?>
        ? payload['operations']
        : payload;
    if (operations == null) return const <SyncOp>[];
    if (operations is! List<Object?>) {
      throw SyncTransportException(
        'Field "operations" is not a list.',
        code: 'sync_invalid_payload',
        statusCode: response.statusCode,
      );
    }
    return OpCodec.decodeList(operations);
  }

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {
    if (closeInjectedClient) client.close();
  }

  Future<PushResult> _pushDocument(String docId, List<SyncOp> ops) async {
    final uri = _opsUri(docId);
    final body = jsonEncode(<String, Object?>{
      'operations': ops.map(OpCodec.encode).toList(growable: false),
    });
    final headers = await _headers();
    final response = await _send(
      () => client.post(uri, headers: headers, body: body),
    );
    final payload = _decodeObject(response.body);
    return PushResult(
      accepted: _decodeOperations(payload['accepted']),
      duplicated: _decodeOperations(payload['duplicated']),
      rejected: _decodeRejected(payload['rejected']),
      lamportAck: _decodeInt(payload['lamport_ack']),
    );
  }

  List<SyncOp> _decodeOperations(Object? raw) {
    if (raw == null) return const <SyncOp>[];
    if (raw is! List<Object?>) {
      throw SyncTransportException(
        'The server returned an invalid list of operations.',
        code: 'sync_invalid_payload',
      );
    }
    return OpCodec.decodeList(raw);
  }

  List<RejectedOperation> _decodeRejected(Object? raw) {
    if (raw == null) return const <RejectedOperation>[];
    if (raw is! List<Object?>) {
      throw SyncTransportException(
        'The server returned an invalid list of rejected operations.',
        code: 'sync_invalid_payload',
      );
    }
    final rejected = <RejectedOperation>[];
    for (final item in raw) {
      if (item is! Map<String, Object?>) continue;
      final Object? key = item['op_id'];
      // The server names the operation it refused when it can: an operation
      // too malformed to be decoded has no identifier, and its refusal must
      // not be dropped.
      final String operationKey = key is String
          ? key
          : 'unknown:${item['field'] ?? 'operations'}';
      rejected.add(
        RejectedOperation(
          operationKey: operationKey,
          code: item['code'] is String ? item['code']! as String : 'rejected',
          message: item['message'] is String
              ? item['message']! as String
              : 'The server refused the operation.',
        ),
      );
    }
    return List<RejectedOperation>.unmodifiable(rejected);
  }

  /// Sends a request and turns the failures into typed errors.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(requestTimeout);
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
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _errorFor(response);
  }

  /// Builds the typed error matching an unsuccessful response.
  SyncException _errorFor(http.Response response) {
    final error = _decodeError(response.body);
    final message =
        error?.message ?? 'The API answered ${response.statusCode}.';
    final code = error?.code;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return SyncAuthException(message, code: code ?? 'sync_unauthorized');
    }
    return SyncTransportException(
      message,
      code: code ?? 'sync_http_error',
      statusCode: response.statusCode,
    );
  }

  /// The `error` envelope of an unsuccessful response.
  ({String code, String message})? _decodeError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return null;
      final error = decoded['error'];
      if (error is! Map<String, Object?>) return null;
      final code = error['code'];
      final message = error['message'];
      return (
        code: code is String ? code : 'sync_http_error',
        message: message is String ? message : 'The request failed.',
      );
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _decodeObject(String body) {
    final Object? decoded = _decodeEnvelope(body);
    if (decoded is! Map<String, Object?>) {
      throw SyncTransportException(
        'The server did not return a JSON object.',
        code: 'sync_invalid_payload',
      );
    }
    return decoded;
  }

  /// Decodes the body of a response and unwraps the envelope of the API.
  ///
  /// Every answer of `apps/limpid_api` is wrapped in `{"data": …}`, and every
  /// error in `{"error": …}`. A transport that reads the fields at the top
  /// level would never find them: the envelope is unwrapped here, once, for
  /// the whole transport.
  Object? _decodeEnvelope(String body) {
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

  int _decodeInt(Object? raw) => raw is int ? raw : 0;

  /// The URI of the operations of a document.
  ///
  /// The identifier is encoded: a `/` inside it would otherwise split the
  /// path and address another route.
  Uri _opsUri(String docId, {Map<String, String>? query}) {
    final path = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(
      path: '$path/v1/projects/${Uri.encodeComponent(docId)}/ops',
      queryParameters: query,
    );
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
