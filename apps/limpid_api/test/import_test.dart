import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_import/limpid_import.dart';
import 'package:limpid_import/testing.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

/// Le carnet Markdown importe par la suite de tests.
const String carnetMarkdown = '''
# Première partie

Un paragraphe de présentation.

- un premier élément
- un second élément

## Premier chapitre

Le texte du premier chapitre.
''';

void main() {
  late TestServer server;
  late Map<String, String> auth;
  late String projectId;

  setUp(() async {
    server = await startTestServer();
    await server.givePlan('user-1', SubscriptionPlan.writer);
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
    projectId = await _createProject(server, auth);
  });

  tearDown(() async {
    await server.stop();
  });

  group('import d\'un manuscrit', () {
    test('cree les chapitres et les scenes', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      expect(response.statusCode, 201);
      final Map<String, dynamic> data = _dataOf(response);
      expect(data['format'], 'markdown');
      expect(data['chapter_count'], 2);
      expect(data['scene_count'], greaterThanOrEqualTo(2));
      expect(data['block_count'], greaterThanOrEqualTo(4));

      final List<dynamic> chapters = data['chapters'] as List<dynamic>;
      expect(chapters, hasLength(2));
      final Map<String, dynamic> first = chapters.first as Map<String, dynamic>;
      expect(first['title'], 'Première partie');
      expect(first['level'], 1);
      expect(first['document_id'], isNotEmpty);
    });

    test('ecrit les documents dans le journal', () async {
      await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      final http.Response tree = await server.get(
        '/v1/projects/$projectId/tree',
        headers: auth,
      );
      expect(tree.statusCode, 200);
      final List<dynamic> documents = _listOf(tree);
      expect(documents, hasLength(2));
      final Map<String, dynamic> document =
          documents.first as Map<String, dynamic>;
      expect(document['meta'], containsPair('title', 'Première partie'));

      // Les blocs sont lisibles : la cle de tri et le parent portent la
      // hierarchie, l'editeur les relit sans rien recalculer.
      final List<dynamic> blocks = document['blocks'] as List<dynamic>;
      expect(blocks, hasLength(3));
      final Map<String, dynamic> first = blocks.first as Map<String, dynamic>;
      expect(first['type'], 'paragraph');
      expect(first['content'], 'Un paragraphe de présentation.');
      final Map<String, dynamic> second = blocks[1] as Map<String, dynamic>;
      expect(second['type'], 'listItem');
      expect(second['content'], 'un premier élément');
    });

    test('n\'ecrase pas le contenu existant', () async {
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
                'content': 'Chapitre deja ecrit',
              },
              'schema_version': 1,
            },
          ],
        },
      );

      await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      final http.Response tree = await server.get(
        '/v1/projects/$projectId/tree',
        headers: auth,
      );
      final List<dynamic> documents = _listOf(tree);
      expect(documents, hasLength(3));
    });

    test('importe un DOCX et annonce les images laissees de cote', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'livre.docx',
          'content': base64Encode(buildDocx()),
        },
      );

      expect(response.statusCode, 201);
      final Map<String, dynamic> data = _dataOf(response);
      expect(data['format'], 'docx');
      expect(data['chapter_count'], 2);
      final List<dynamic> skipped = data['skipped'] as List<dynamic>;
      expect(skipped, hasLength(1));
      expect((skipped.first as Map<String, dynamic>)['reason'], 'images');
    });

    test('journalise l\'import dans l\'audit', () async {
      await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      expect(
        server.audit.entries.any(
          (AuditEntry entry) => entry.action == 'project.imported',
        ),
        isTrue,
      );
    });

    test('refuse un format inconnu avec 415', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'livre.pdf',
          'content': base64Encode(utf8.encode('%PDF-1.7')),
        },
      );

      expect(response.statusCode, 415);
      final Map<String, dynamic> error = _errorOf(response);
      expect(error['code'], ImportErrorCodes.unsupportedFormat);
      expect(
        (error['details'] as Map<String, dynamic>)['formats'],
        contains('docx'),
      );
    });

    test('refuse un fichier illisible', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'livre.docx',
          'content': base64Encode(utf8.encode('ceci n est pas un paquet')),
        },
      );

      expect(response.statusCode, 400);
      expect(_errorOf(response)['code'], ErrorCodes.validationFailed);
    });

    test('refuse un contenu qui n\'est pas du base64', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': 'ceci n est pas du base64 !!!',
        },
      );

      expect(response.statusCode, 400);
      expect(_errorOf(response)['code'], ErrorCodes.validationFailed);
    });

    test('refuse un appelant sans jeton', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/import',
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      expect(response.statusCode, 401);
    });

    test('refuse un projet qui n\'existe pas', () async {
      final http.Response response = await server.post(
        '/v1/projects/inconnu/import',
        headers: auth,
        body: <String, Object?>{
          'file_name': 'carnet.md',
          'content': base64Encode(utf8.encode(carnetMarkdown)),
        },
      );

      expect(response.statusCode, 404);
    });
  });
}

/// The `data` envelope of a response.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return payload['data'] as Map<String, dynamic>;
}

/// The `data` envelope of a response, quand elle porte une liste.
List<dynamic> _listOf(http.Response response) {
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return payload['data'] as List<dynamic>;
}

/// The `error` envelope of a response.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return payload['error'] as Map<String, dynamic>;
}

/// Cree un projet et rend son identifiant.
Future<String> _createProject(
  TestServer server,
  Map<String, String> auth,
) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: auth,
    body: <String, Object?>{'title': 'Le livre'},
  );
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (payload['data'] as Map<String, dynamic>)['id'] as String;
}
