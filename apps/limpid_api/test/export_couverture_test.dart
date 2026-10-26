import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

/// L'ISBN de l'edition imprimee preparee par les tests.
const String _isbn = '9782264000002';

/// Le texte des flux de contenu d'un PDF.
///
/// Les flux sont compresses : ils sont decompresses a la volee, puis les
/// chaines de texte sont concatenees. C'est la lecture la plus simple du
/// contenu imprime : elle dit ce que l'auteur voit sur le papier.
String _pdfText(List<int> bytes) {
  final String raw = latin1.decode(bytes, allowInvalid: true);
  final StringBuffer builder = StringBuffer();
  for (final RegExpMatch match in RegExp('stream\r?\n').allMatches(raw)) {
    final int start = match.end;
    final int end = raw.indexOf('endstream', start);
    if (end < 0) continue;
    final List<int> inflated;
    try {
      inflated = ZLibDecoder().convert(
        latin1.encode(raw.substring(start, end)),
      );
    } on Object {
      continue;
    }
    final String stream = latin1.decode(inflated, allowInvalid: true);
    for (final RegExpMatch text in RegExp(
      r'\[\((.*?)\)\]TJ',
    ).allMatches(stream)) {
      builder.write(text.group(1));
      builder.write(' ');
    }
  }
  return builder.toString();
}

/// Prepare une publication Amazon KDP pour le projet.
///
/// La fiche porte l'ISBN : c'est elle que l'export relit.
Future<void> _preparePublication(
  TestServer server,
  Map<String, String> headers,
  String projectId,
) async {
  final http.Response response = await server.post(
    '/v1/publishing/kdp',
    headers: headers,
    body: <String, Object?>{
      'project_id': projectId,
      'title': 'La Falaise',
      'author': 'Camille Rivière',
      'description': 'Un roman maritime sur une côte battue par les vents.',
      'keywords': <String>['roman maritime'],
      'categories': <String>['Romans français'],
      'isbn': _isbn,
    },
  );
  expect(response.statusCode, 201, reason: 'La préparation doit aboutir.');
}

void main() {
  late TestServer server;
  late Map<String, String> auth;
  late String projectId;

  setUp(() async {
    server = await startTestServer();
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
    projectId = await _createProject(server, auth);
    await server.post(
      '/v1/projects/$projectId/ops',
      headers: auth,
      body: <String, Object?>{
        'operations': <dynamic>[
          <String, Object?>{
            'op_id': 'op-1',
            'doc_id': 'doc-1',
            'lamport': 1,
            'author_id': 'user-1',
            'type': 'insertBlock',
            'payload': <String, Object?>{
              'block_id': 'block-1',
              'parent_id': null,
              'order_key': '5',
              'type': 'heading1',
              'content': 'Chapitre premier',
            },
            'schema_version': 1,
          },
          <String, Object?>{
            'op_id': 'op-2',
            'doc_id': 'doc-1',
            'lamport': 2,
            'author_id': 'user-1',
            'type': 'insertBlock',
            'payload': <String, Object?>{
              'block_id': 'block-2',
              'parent_id': 'block-1',
              'order_key': '7',
              'type': 'paragraph',
              'content':
                  'Il pleuvait sur la falaise, et le vent portait le '
                  'goût du sel jusqu\'à la maison.',
            },
            'schema_version': 1,
          },
        ],
      },
    );
  });

  tearDown(() async {
    await server.stop();
  });

  group('export et couverture', () {
    test('le code-barres de l\'ISBN atteint l\'export imprime', () async {
      await _givePrintPlan(server, auth);
      await _preparePublication(server, auth, projectId);

      final http.Response response = await server.post(
        '/v1/export/pdf-print',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 200);
      final String text = _pdfText(response.bodyBytes);
      // Les chiffres du code-barres sont imprimes, regroupes selon la
      // norme EAN-13.
      expect(
        RegExp(r'9\s+782264\s+000002').hasMatch(text),
        isTrue,
        reason: 'Le code-barres doit porter les chiffres de l\'ISBN.',
      );
      expect(text.replaceAll(' ', ''), contains(_isbn));
    });

    test('un livre sans ISBN n\'imprime aucun code-barres', () async {
      await _givePrintPlan(server, auth);

      final http.Response response = await server.post(
        '/v1/export/pdf-print',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 200);
      expect(
        _pdfText(response.bodyBytes).replaceAll(' ', ''),
        isNot(contains(_isbn)),
      );
    });

    test('la maquette complete est exposee', () async {
      await _givePrintPlan(server, auth);

      final http.Response response = await server.post(
        '/v1/export/pdf-print',
        headers: auth,
        body: <String, Object?>{'project_id': projectId, 'cover': 'full'},
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/pdf'));
    });

    test('la couverture de face est le defaut', () async {
      await _givePrintPlan(server, auth);

      final http.Response response = await server.post(
        '/v1/export/pdf-print',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/pdf'));
    });

    test('une couverture inconnue est refusee et nommee', () async {
      await _givePrintPlan(server, auth);

      final http.Response response = await server.post(
        '/v1/export/pdf-print',
        headers: auth,
        body: <String, Object?>{'project_id': projectId, 'cover': 'dos'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['message'], contains('cover'));
    });
  });
}

/// Donne au compte la formule qui ouvre les exports imprimes.
///
/// La formule Pro exige la double authentification (D-19) : la preuve
/// accompagne les appels.
Future<void> _givePrintPlan(
  TestServer server,
  Map<String, String> headers,
) async {
  await server.givePlan('user-1', SubscriptionPlan.pro);
  headers['x-limpid-2fa'] = await server.enableTwoFactor('user-1');
}

/// Crée un projet et rend son identifiant.
Future<String> _createProject(
  TestServer server,
  Map<String, String> headers, [
  String title = 'Manuscrit',
]) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': title},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}
