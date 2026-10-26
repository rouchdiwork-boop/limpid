import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late String token;
  late Map<String, String> auth;
  late String projectId;

  setUp(() async {
    server = await startTestServer();
    token = server.tokenFor('user-1');
    auth = <String, String>{'authorization': 'Bearer $token'};
    projectId = await _createProject(server, auth);
  });

  tearDown(() async {
    await server.stop();
  });

  Map<String, Object?> operation({
    int lamport = 1,
    String type = 'insertBlock',
    String docId = 'doc-1',
    String authorId = 'user-1',
    Map<String, Object?> payload = const <String, Object?>{
      'block_id': 'block-1',
      'parent_id': null,
      'order_key': '5',
      'type': 'paragraph',
      'content': 'Il pleuvait sur la falaise.',
    },
    int schemaVersion = 1,
  }) {
    return <String, Object?>{
      'op_id': 'op-$lamport',
      'doc_id': docId,
      'lamport': lamport,
      'author_id': authorId,
      'type': type,
      'payload': payload,
      'schema_version': schemaVersion,
    };
  }

  group('push des opérations', () {
    test('accepte une opération et l\'acquitte', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation()],
        },
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['accepted'], hasLength(1));
      expect(data['duplicated'], isEmpty);
      expect(data['rejected'], isEmpty);
      expect(data['lamport_ack'], 1);
    });

    test('est idempotent sur (doc, lamport, author)', () async {
      await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation()],
        },
      );

      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation()],
        },
      );

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['accepted'], isEmpty);
      expect(data['duplicated'], hasLength(1));
      expect(server.sync.storedOperations(projectId), hasLength(1));
    });

    test('isole une opération invalide sans rejeter le lot', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[
            operation(),
            <String, Object?>{'op_id': 'op-kasche', 'lamport': 2},
          ],
        },
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['accepted'], hasLength(1));
      expect(data['rejected'], hasLength(1));
      expect(
        (data['rejected']! as List<dynamic>).first,
        containsPair('field', 'doc_id'),
      );
    });

    test('répond 400 quand la liste des opérations manque', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{'ops': <dynamic>[]},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('operations'),
      );
    });

    test('refuse une version de protocole trop ancienne', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation(schemaVersion: 0)],
        },
      );

      expect(response.statusCode, 409);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['code'],
        'schema_version_unsupported',
      );
    });

    test('refuse une version de protocole trop récente', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation(schemaVersion: 99)],
        },
      );

      expect(response.statusCode, 426);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'client_ahead');
    });

    test('appose l\'auteur de l\'appelant sur une opération', () async {
      final http.Response response = await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation(authorId: 'user-9')],
        },
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data =
          (jsonDecode(response.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final List<dynamic> accepted = data['accepted'] as List<dynamic>;
      expect(accepted, hasLength(1));
      expect((accepted.first as Map<String, dynamic>)['author_id'], 'user-1');
      expect(server.sync.storedOperations(projectId).first.authorId, 'user-1');
    });

    test('refuse une opération sur le document d\'un autre projet', () async {
      await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[operation()],
        },
      );

      final Map<String, String> otherAuth = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-2')}',
      };
      final String otherProjectId = await _createProject(server, otherAuth);

      final http.Response response = await server.post(
        '/v1/projects/$otherProjectId/ops',
        headers: otherAuth,
        body: <String, Object?>{
          'operations': <dynamic>[operation(lamport: 2)],
        },
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data =
          (jsonDecode(response.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data['accepted'], isEmpty);
      final List<dynamic> rejected = data['rejected'] as List<dynamic>;
      expect(rejected, hasLength(1));
      expect((rejected.first as Map<String, dynamic>)['code'], 'not_found');
      expect(server.sync.storedOperations(otherProjectId), isEmpty);
    });
  });

  group('pull des opérations', () {
    test('renvoie les opérations postérieures à "since"', () async {
      await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[
            operation(lamport: 1),
            operation(
              lamport: 2,
              payload: <String, Object?>{'block_id': 'block-2'},
              type: 'deleteBlock',
            ),
          ],
        },
      );

      final http.Response all = await server.get(
        '/v1/projects/$projectId/ops?since=0',
        headers: auth,
      );
      expect(jsonDecode(all.body)['data'], hasLength(2));

      final http.Response recent = await server.get(
        '/v1/projects/$projectId/ops?since=1',
        headers: auth,
      );
      final List<dynamic> data =
          jsonDecode(recent.body)['data'] as List<dynamic>;
      expect(data, hasLength(1));
      expect((data.first as Map<String, dynamic>)['lamport'], 2);
    });

    test('refuse un "since" invalide', () async {
      final http.Response response = await server.get(
        '/v1/projects/$projectId/ops?since=abc',
        headers: auth,
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('since'),
      );
    });
  });

  group('arbre du projet', () {
    test('reconstruit les blocs du document', () async {
      await server.post(
        '/v1/projects/$projectId/ops',
        headers: auth,
        body: <String, Object?>{
          'operations': <dynamic>[
            operation(),
            operation(
              lamport: 2,
              payload: <String, Object?>{
                'block_id': 'block-2',
                'parent_id': 'block-1',
                'order_key': '7',
                'type': 'paragraph',
                'content': 'Deuxième paragraphe.',
              },
            ),
          ],
        },
      );

      final http.Response response = await server.get(
        '/v1/projects/$projectId/tree',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final List<dynamic> data =
          jsonDecode(response.body)['data'] as List<dynamic>;
      expect(data, hasLength(1));

      final Map<String, dynamic> document = data.first as Map<String, dynamic>;
      expect(document['doc_id'], 'doc-1');
      expect(document['lamport'], 2);

      final List<dynamic> blocks = document['blocks'] as List<dynamic>;
      expect(blocks, hasLength(1));

      final Map<String, dynamic> root = blocks.first as Map<String, dynamic>;
      expect(root['id'], 'block-1');
      expect(root['content'], 'Il pleuvait sur la falaise.');
      expect(root['children'], hasLength(1));
      expect(
        ((root['children']! as List<dynamic>).first
            as Map<String, dynamic>)['id'],
        'block-2',
      );
    });

    test('répond 404 sur un projet inconnu', () async {
      final http.Response response = await server.get(
        '/v1/projects/inconnu/tree',
        headers: auth,
      );

      expect(response.statusCode, 404);
    });
  });
}

Future<String> _createProject(
  TestServer server,
  Map<String, String> headers,
) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': 'Manuscrit'},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}
