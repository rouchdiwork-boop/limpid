import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> auth;
  late Map<String, String> otherAuth;

  setUp(() async {
    server = await startTestServer();
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
    otherAuth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-2')}',
    };
  });

  tearDown(() async {
    await server.stop();
  });

  group('export des données personnelles', () {
    test(
      'renvoie les projets, les documents, les opérations et l\'audit',
      () async {
        final String projectId = await _createProject(server, auth, 'Le livre');
        await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');

        final http.Response response = await server.get(
          '/v1/me/export',
          headers: auth,
        );

        expect(response.statusCode, 200);
        final Map<String, dynamic> data = _dataOf(response);

        final List<dynamic> projects = data['projects'] as List<dynamic>;
        expect(projects, hasLength(1));

        final Map<String, dynamic> project =
            projects.single as Map<String, dynamic>;
        expect((project['project'] as Map<String, dynamic>)['id'], projectId);
        expect(
          (project['project'] as Map<String, dynamic>)['owner_id'],
          'user-1',
        );

        final List<dynamic> documents = project['documents'] as List<dynamic>;
        expect(documents, hasLength(1));
        expect((documents.single as Map<String, dynamic>)['doc_id'], 'doc-1');

        final List<dynamic> operations =
            project['sync_operations'] as List<dynamic>;
        expect(operations, hasLength(1));
        expect(
          (operations.first as Map<String, dynamic>)['author_id'],
          'user-1',
        );

        final List<dynamic> chapters = project['chapters'] as List<dynamic>;
        expect(chapters, hasLength(1));
        final List<dynamic> scenes =
            (chapters.single as Map<String, dynamic>)['scenes']
                as List<dynamic>;
        expect((scenes.single as Map<String, dynamic>)['document_id'], 'doc-1');

        final Map<String, dynamic> counts =
            data['counts'] as Map<String, dynamic>;
        expect(counts['projects'], 1);
        expect(counts['documents'], 1);
        expect(counts['sync_operations'], 1);
      },
    );

    test('ne renvoie pas les données d\'un autre auteur', () async {
      final String mine = await _createProject(server, auth, 'Le mien');
      await _pushScene(server, auth, mine, 'doc-mine', 'Ma scène');

      final String theirs = await _createProject(server, otherAuth, 'Le sien');
      await _pushScene(
        server,
        otherAuth,
        theirs,
        'doc-theirs',
        'Sa scène',
        'user-2',
      );
      await server.delete('/v1/projects/$theirs', headers: otherAuth);

      final http.Response response = await server.get(
        '/v1/me/export',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final String body = response.body;
      expect(body, contains(mine));
      expect(body, isNot(contains(theirs)));
      expect(body, isNot(contains('doc-theirs')));
      expect(body, isNot(contains('Sa scène')));

      final Map<String, dynamic> data = _dataOf(response);
      final List<dynamic> entries = data['audit_log'] as List<dynamic>;
      expect(entries, isEmpty);
    });

    test('journalise la demande dans l\'audit', () async {
      await server.get('/v1/me/export', headers: auth);

      expect(
        server.audit.entries.any(
          (AuditEntry entry) =>
              entry.action == 'account.export_requested' &&
              entry.userId == 'user-1',
        ),
        isTrue,
      );
    });

    test(
      'porte aussi les projets supprimés, qui vivent encore trente jours',
      () async {
        final String projectId = await _createProject(server, auth, 'Le livre');
        await server.delete('/v1/projects/$projectId', headers: auth);

        final http.Response response = await server.get(
          '/v1/me/export',
          headers: auth,
        );

        expect(response.statusCode, 200);
        final List<dynamic> projects =
            _dataOf(response)['projects'] as List<dynamic>;
        expect(projects, hasLength(1));
        final Map<String, Object?> project =
            (projects.single as Map<String, Object?>)['project']
                as Map<String, Object?>;
        expect(project['id'], projectId);
        expect(project['deleted_at'], isA<String>());
      },
    );

    test('exige une authentification', () async {
      final http.Response response = await server.get('/v1/me/export');

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'unauthorized');
    });
  });

  group('suppression du compte', () {
    test('exige la confirmation explicite', () async {
      final http.Response withoutBody = await server.delete(
        '/v1/me',
        headers: auth,
      );
      expect(withoutBody.statusCode, 400);

      final http.Response refused = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': false},
      );
      expect(refused.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(refused.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['code'],
        'validation_failed',
      );
      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        isEmpty,
      );
    });

    test('journalise la demande et fixe l\'échéance à trente jours', () async {
      final http.Response response = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(response);
      expect(data['status'], 'pending_deletion');
      expect(data['retention_days'], 30);

      final DateTime requestedAt = DateTime.parse(
        data['requested_at'] as String,
      );
      final DateTime scheduledFor = DateTime.parse(
        data['scheduled_for'] as String,
      );
      expect(scheduledFor.difference(requestedAt).inDays, 30);

      final List<AuditEntry> deletions = server.audit.entries
          .where(
            (AuditEntry candidate) =>
                candidate.action == 'account.deletion_requested',
          )
          .toList(growable: false);
      expect(deletions, hasLength(1));
      final AuditEntry entry = deletions.single;
      expect(entry.userId, 'user-1');
      expect(entry.targetType, 'account');
      expect(entry.metadata['retention_days'], 30);
    });

    test('est idempotente', () async {
      final http.Response first = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );
      final http.Response second = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(_dataOf(second), _dataOf(first));

      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        hasLength(1),
      );
    });

    test('exige une authentification', () async {
      final http.Response response = await server.delete(
        '/v1/me',
        body: <String, Object?>{'confirm': true},
      );

      expect(response.statusCode, 401);
    });

    test('reste idempotente quand le journal grandit', () async {
      final http.Response first = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      for (var index = 0; index < 60; index++) {
        server.audit.entries.add(
          AuditEntry(
            userId: 'user-1',
            action: 'export.requested',
            targetType: 'project',
            targetId: 'projet-$index',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      final http.Response second = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(_dataOf(second), _dataOf(first));
      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        hasLength(1),
      );
    });
  });
}

Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>;
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

Future<void> _pushScene(
  TestServer server,
  Map<String, String> headers,
  String projectId,
  String docId,
  String content, [
  String authorId = 'user-1',
]) async {
  await server.post(
    '/v1/projects/$projectId/ops',
    headers: headers,
    body: <String, Object?>{
      'operations': <dynamic>[
        <String, Object?>{
          'op_id': '$docId-op-1',
          'doc_id': docId,
          'lamport': 1,
          'author_id': authorId,
          'type': 'insertBlock',
          'payload': <String, Object?>{
            'block_id': '$docId-block-1',
            'parent_id': null,
            'order_key': '5',
            'type': 'paragraph',
            'content': content,
          },
          'schema_version': 1,
        },
      ],
    },
  );
}
