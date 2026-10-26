import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A fake [http.BaseClient] recording the requests and answering with canned
/// responses.
///
/// It replaces the network in the tests: no socket is ever opened.
final class FakeHttpClient extends http.BaseClient {
  /// Creates a client answering with [handler].
  FakeHttpClient(this.handler);

  /// Creates a client always answering with the same JSON body.
  factory FakeHttpClient.json(String body, {int statusCode = 200}) {
    return FakeHttpClient(
      (request) async => jsonStreamedResponse(body, statusCode: statusCode),
    );
  }

  /// Answers the requests of the client.
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  /// The requests received by the client, in order.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// The number of requests received.
  int get callCount => requests.length;

  /// The decoded JSON bodies of the requests that carried one.
  List<Map<String, Object?>> get jsonBodies => requests
      .whereType<http.Request>()
      .map((request) => jsonDecode(request.body) as Map<String, Object?>)
      .toList(growable: false);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return handler(request);
  }
}

/// A client that always fails like an unreachable network.
final class UnreachableHttpClient extends http.BaseClient {
  /// Creates a client that always fails.
  UnreachableHttpClient({this.message = 'The host could not be reached.'});

  /// The message carried by the failure.
  final String message;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw http.ClientException(message, request.url);
  }
}

/// Builds a JSON [http.StreamedResponse].
http.StreamedResponse jsonStreamedResponse(
  String body, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
