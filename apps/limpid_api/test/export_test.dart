import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> auth;
  late String projectId;

  setUp(() async {
    server = await startTestServer();
    // La formule gratuite n'autorise qu'un projet : les tests qui en
    // creent plusieurs donnent la formule Ecrivain.
    await server.givePlan('user-1', SubscriptionPlan.writer);
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

  group('export', () {
    test('renvoie le fichier EPUB et le stocke', () async {
      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        contains('application/epub+zip'),
      );
      expect(response.headers['content-disposition'], contains('attachment'));
      expect(response.bodyBytes, isNotEmpty);
      expect(server.storage.keys.single, startsWith('exports/$projectId/'));
    });

    test('renvoie le fichier Markdown', () async {
      final http.Response response = await server.post(
        '/v1/export/md',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/markdown'));
      expect(response.body, contains('Il pleuvait sur la falaise'));
    });

    test('journalise l\'export dans l\'audit', () async {
      await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(
        server.audit.entries.any(
          (AuditEntry entry) => entry.action == 'export.requested',
        ),
        isTrue,
      );
    });

    test('répond 400 et nomme le format inconnu', () async {
      final http.Response response = await server.post(
        '/v1/export/inconnu',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('format'),
      );
    });

    test('répond 400 quand le projet manque', () async {
      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('project_id'),
      );
    });

    test('répond 404 sur un projet inconnu', () async {
      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': 'inconnu'},
      );

      expect(response.statusCode, 404);
    });

    test('refuse l\'export d\'un projet sans contenu', () async {
      final String empty = await _createProject(server, auth, 'Vide');

      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': empty},
      );

      expect(response.statusCode, 409);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'conflict');
    });
  });
}

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
