import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client HTTP factice : aucune requête ne sort du processus.
///
/// Le corps de la réponse est scripté par le test, ce qui permet de rejouer des
/// flux SSE ou NDJSON sans serveur.
class FakeHttpClient extends http.BaseClient {
  /// Crée un client factice.
  FakeHttpClient(this._handler);

  /// Réponse à renvoyer pour chaque requête.
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  /// Requêtes reçues, dans l'ordre.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// Dernière requête reçue.
  http.BaseRequest get lastRequest => requests.last;

  /// Corps JSON de la dernière requête.
  Map<String, dynamic> get lastJsonBody {
    final http.BaseRequest request = lastRequest;
    if (request is! http.Request) {
      throw StateError('La dernière requête n\'est pas de type http.Request.');
    }
    final Object? decoded = jsonDecode(request.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Le corps de la requête n\'est pas un objet JSON.');
    }
    return decoded;
  }

  /// En-têtes de la dernière requête.
  Map<String, String> get lastHeaders => lastRequest.headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return _handler(request);
  }
}

/// Construit une réponse HTTP dont le corps est envoyé en une seule fois.
http.StreamedResponse fakeResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) {
  final List<int> bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    contentLength: bytes.length,
    headers: headers,
  );
}

/// Construit une réponse HTTP dont le corps est envoyé fragment par fragment.
///
/// Les fragments sont coupés au milieu des lignes, afin d'éprouver le
/// décodage UTF-8 et le découpage ligne à ligne.
http.StreamedResponse fakeChunkedResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
  int chunkSize = 17,
}) {
  final List<int> bytes = utf8.encode(body);
  final List<List<int>> chunks = <List<int>>[];
  for (int offset = 0; offset < bytes.length; offset += chunkSize) {
    final int end = (offset + chunkSize).clamp(0, bytes.length);
    chunks.add(bytes.sublist(offset, end));
  }
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(chunks),
    statusCode,
    contentLength: bytes.length,
    headers: headers,
  );
}
