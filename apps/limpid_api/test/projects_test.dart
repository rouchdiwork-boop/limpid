import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late String token;
  late Map<String, String> auth;

  setUp(() async {
    server = await startTestServer();
    token = server.tokenFor('user-1');
    auth = <String, String>{'authorization': 'Bearer $token'};
  });

  tearDown(() async {
    await server.stop();
  });

  group('cycle de vie des projets', () {
    test('crée un projet et le renvoie dans l\'enveloppe data', () async {
      final http.Response response = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{
          'title': 'Le Vent de Nord',
          'synopsis': 'Un-cold, un village, uneLongitude.',
        },
      );

      expect(response.statusCode, 201);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['title'], 'Le Vent de Nord');
      expect(data['owner_id'], 'user-1');
      expect(data['status'], 'draft');
      expect(data['language'], 'fr-FR');
      expect(data['id'], isA<String>());
    });

    test('lit le projet créé', () async {
      final String id = await _createProject(server, auth, 'Titre');

      final http.Response response = await server.get(
        '/v1/projects/$id',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['data'] as Map<String, dynamic>)['id'], id);
    });

    test('met à jour le titre du projet', () async {
      final String id = await _createProject(server, auth, 'Titre');

      final http.Response response = await server.patch(
        '/v1/projects/$id',
        headers: auth,
        body: <String, Object?>{'title': 'Titre corrigé', 'status': 'writing'},
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;
      expect(data['title'], 'Titre corrigé');
      expect(data['status'], 'writing');
    });

    test('supprime le projet et le journalise dans l\'audit', () async {
      final String id = await _createProject(server, auth, 'Titre');

      final http.Response response = await server.delete(
        '/v1/projects/$id',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['data'] as Map<String, dynamic>)['deleted'], isTrue);
      expect(
        server.audit.entries.any(
          (AuditEntry entry) =>
              entry.action == 'project.deleted' && entry.targetId == id,
        ),
        isTrue,
      );

      final http.Response afterDelete = await server.get(
        '/v1/projects/$id',
        headers: auth,
      );
      expect(afterDelete.statusCode, 404);
    });

    test('isole les projets des autres comptes', () async {
      final String id = await _createProject(server, auth, 'Titre');
      final String otherToken = server.tokenFor('user-2');

      final http.Response response = await server.get(
        '/v1/projects/$id',
        headers: <String, String>{'authorization': 'Bearer $otherToken'},
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'not_found');
    });

    test(
      'autorise la lecture mais pas l\'écriture aux bêta-lecteurs',
      () async {
        final String id = await _createProject(server, auth, 'Titre');
        server.projects.addMember(
          projectId: id,
          userId: 'user-2',
          role: ProjectRole.betaReader,
        );
        final Map<String, String> reader = <String, String>{
          'authorization': 'Bearer ${server.tokenFor('user-2')}',
        };

        final http.Response read = await server.get(
          '/v1/projects/$id',
          headers: reader,
        );
        expect(read.statusCode, 200);

        final http.Response write = await server.post(
          '/v1/projects/$id/ops',
          headers: reader,
          body: <String, Object?>{'operations': <dynamic>[]},
        );
        expect(write.statusCode, 403);
        final Map<String, dynamic> body =
            jsonDecode(write.body) as Map<String, dynamic>;
        expect((body['error'] as Map<String, dynamic>)['code'], 'forbidden');
      },
    );
  });

  group('erreurs', () {
    test('répond 404 et "not_found" sur une ressource inconnue', () async {
      final http.Response response = await server.get(
        '/v1/projects/project-inconnu',
        headers: auth,
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'not_found');
      expect(error['message'], isA<String>());
      expect(error['details'], isA<Map<String, dynamic>>());
    });

    test('répond 404 sur une route inconnue', () async {
      final http.Response response = await server.get(
        '/v1/inconnu',
        headers: auth,
      );

      expect(response.statusCode, 404);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'not_found');
    });

    test('répond 400 et nomme le champ manquant', () async {
      final http.Response response = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'synopsis': 'Sans titre.'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'validation_failed');
      expect(error['message'], contains('title'));
    });

    test('répond 400 et nomme le champ mal typé', () async {
      final http.Response response = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'title': 42},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'validation_failed');
      expect(error['message'], contains('title'));
    });

    test('répond 400 sur un corps JSON invalide', () async {
      final http.Response response = await http.post(
        Uri.parse('${server.baseUrl}/v1/projects'),
        headers: <String, String>{...auth, 'content-type': 'application/json'},
        body: '{pas du json',
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['code'],
        'validation_failed',
      );
    });

    test('répond 400 sur un statut inconnu', () async {
      final http.Response response = await server.post(
        '/v1/projects',
        headers: auth,
        body: <String, Object?>{'title': 'Titre', 'status': 'inconnu'},
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('status'),
      );
    });
  });

  group('pagination', () {
    test(
      'respecte la limite demandée et renvoie un curseur cohérent',
      () async {
        for (var i = 0; i < 5; i++) {
          await _createProject(server, auth, 'Projet $i');
        }

        final http.Response response = await server.get(
          '/v1/projects?limit=2',
          headers: auth,
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> body =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> data = body['data'] as List<dynamic>;
        final Map<String, dynamic> meta = body['meta'] as Map<String, dynamic>;

        expect(data, hasLength(2));
        expect(meta['limit'], 2);
        expect(meta['page'], 1);
        expect(meta['total'], 5);
        expect(meta['next_cursor'], isA<String>());

        final http.Response second = await server.get(
          '/v1/projects?limit=2&cursor=${meta['next_cursor']}',
          headers: auth,
        );
        final Map<String, dynamic> secondBody =
            jsonDecode(second.body) as Map<String, dynamic>;
        final List<dynamic> secondData = secondBody['data'] as List<dynamic>;

        expect(secondData, hasLength(2));
        final List<String> firstIds = data
            .map(
              (dynamic item) => (item as Map<String, dynamic>)['id'] as String,
            )
            .toList();
        final List<String> secondIds = secondData
            .map(
              (dynamic item) => (item as Map<String, dynamic>)['id'] as String,
            )
            .toList();
        expect(firstIds.toSet().intersection(secondIds.toSet()), isEmpty);
      },
    );

    test('refuse une limite supérieure au maximum', () async {
      final http.Response response = await server.get(
        '/v1/projects?limit=5000',
        headers: auth,
      );

      expect(response.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['message'],
        contains('limit'),
      );
    });
  });
}

Future<String> _createProject(
  TestServer server,
  Map<String, String> headers,
  String title,
) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': title},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}
