import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart' hide ExportJobStatus;
import 'package:test/test.dart';

import 'helpers/export_test_server.dart';

void main() {
  group('export', () {
    late ExportTestServer server;
    late Map<String, String> auth;
    late String projectId;

    setUp(() async {
      server = await ExportTestServer.start();
      // La formule gratuite n'autorise qu'un projet : les tests qui en
      // creent plusieurs donnent la formule Ecrivain.
      await server.givePlan('user-1', SubscriptionPlan.writer);
      auth = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-1')}',
      };
      projectId = await _createProject(server, auth);
      await _pushContent(server, auth, projectId);
    });

    tearDown(() async {
      await server.stop();
    });

    test('la route répond aussitot et ne fabrique pas le livre', () async {
      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 202);
      final Map<String, dynamic> job = _dataOf(response);
      expect(job['status'], ExportJobStatus.queued.key);
      expect(job['id'], isNotEmpty);
      // L'export n'a pas été fait dans la requête : le stockage est vide.
      expect(server.storage.keys, isEmpty);
    });

    test('le worker produit l\'artefact et le travail aboutit', () async {
      final String jobId = await _requestExport(server, auth, projectId);

      await server.runWorker();

      final ExportJobRecord? job = await server.job(jobId);
      expect(job, isNotNull);
      expect(job!.status, ExportJobStatus.succeeded);
      expect(job.error, isNull);
      expect(job.artifactKey, startsWith('exports/$projectId/'));
      expect(job.expiresAt, isNotNull);
      expect(server.storage.keys.single, startsWith('exports/$projectId/'));
    });

    test('la consultation dit où en est le travail', () async {
      final String jobId = await _requestExport(server, auth, projectId);

      final http.Response running = await server.get(
        '/v1/exports/$jobId',
        headers: auth,
      );
      expect(running.statusCode, 200);
      expect(_dataOf(running)['status'], ExportJobStatus.queued.key);

      await server.runWorker();

      final http.Response ready = await server.get(
        '/v1/exports/$jobId',
        headers: auth,
      );
      expect(_dataOf(ready)['status'], ExportJobStatus.succeeded.key);
      expect(_dataOf(ready)['download_url'], isNotEmpty);
    });

    test('la liste des travaux rend ceux du compte', () async {
      final String jobId = await _requestExport(server, auth, projectId);

      final http.Response response = await server.get(
        '/v1/exports',
        headers: auth,
      );

      expect(response.statusCode, 200);
      final List<dynamic> jobs = _listOf(response);
      expect(jobs, hasLength(1));
      expect((jobs.single as Map<String, dynamic>)['id'], jobId);
    });

    test('un travail en échec ne consomme rien', () async {
      final ExportTestServer broken = await ExportTestServer.start(
        storage: _FailingStorage(),
      );
      addTearDown(broken.stop);
      await broken.givePlan('user-1', SubscriptionPlan.writer);
      final Map<String, String> headers = <String, String>{
        'authorization': 'Bearer ${broken.tokenFor('user-1')}',
      };
      final String book = await _createProject(broken, headers);
      await _pushContent(broken, headers, book);

      final String jobId = await _requestExport(broken, headers, book);
      await broken.runWorker();

      final ExportJobRecord? job = await broken.job(jobId);
      expect(job!.status, ExportJobStatus.failed);
      expect(job.error, isNotEmpty);
      expect(job.artifactKey, isNull);
      // L'échec ne consomme rien : le compteur reste à zéro.
      expect(await _exportsUsed(broken), 0);
    });

    test(
      'l\'échec propose une relance, et la relance crée un travail neuf',
      () async {
        final ExportTestServer broken = await ExportTestServer.start(
          storage: _FailingStorage(),
        );
        addTearDown(broken.stop);
        await broken.givePlan('user-1', SubscriptionPlan.writer);
        final Map<String, String> headers = <String, String>{
          'authorization': 'Bearer ${broken.tokenFor('user-1')}',
        };
        final String book = await _createProject(broken, headers);
        await _pushContent(broken, headers, book);

        final String jobId = await _requestExport(broken, headers, book);
        await broken.runWorker();

        final http.Response retry = await broken.post(
          '/v1/exports/$jobId/retry',
          headers: headers,
          body: <String, Object?>{},
        );

        expect(retry.statusCode, 202);
        final Map<String, dynamic> fresh = _dataOf(retry);
        expect(fresh['id'], isNot(jobId));
        expect(fresh['status'], ExportJobStatus.queued.key);
        // Le travail en échec reste un événement : il n'est pas rejoué.
        final ExportJobRecord? failed = await broken.job(jobId);
        expect(failed!.status, ExportJobStatus.failed);
      },
    );

    test('un travail qui n\'a pas échoué ne se relance pas', () async {
      final String jobId = await _requestExport(server, auth, projectId);

      final http.Response retry = await server.post(
        '/v1/exports/$jobId/retry',
        headers: auth,
        body: <String, Object?>{},
      );

      expect(retry.statusCode, 409);
    });

    test(
      'l\'artefact reste téléchargeable quinze minutes, puis l\'adresse refuse',
      () async {
        DateTime now = DateTime.utc(2026, 10, 26, 9);
        final ExportTestServer timed = await ExportTestServer.start(
          clock: () => now,
        );
        addTearDown(timed.stop);
        await timed.givePlan('user-1', SubscriptionPlan.writer);
        final Map<String, String> headers = <String, String>{
          'authorization': 'Bearer ${timed.tokenFor('user-1')}',
        };
        final String book = await _createProject(timed, headers);
        await _pushContent(timed, headers, book);

        final String jobId = await _requestExport(timed, headers, book);
        await timed.runWorker();

        final http.Response fresh = await timed.get(
          '/v1/exports/$jobId/download',
          headers: headers,
        );
        expect(fresh.statusCode, 200);
        final Map<String, dynamic> address = _dataOf(fresh);
        expect(address['download_url'], isNotEmpty);
        expect(
          DateTime.parse(address['expires_at']! as String),
          now.add(exportArtifactLifetime),
        );

        // Quinze minutes plus tard, l'adresse refuse de servir le fichier.
        now = now.add(exportArtifactLifetime + const Duration(minutes: 1));

        final http.Response expired = await timed.get(
          '/v1/exports/$jobId/download',
          headers: headers,
        );
        expect(expired.statusCode, 404);
        final http.Response consultation = await timed.get(
          '/v1/exports/$jobId',
          headers: headers,
        );
        expect(_dataOf(consultation)['download_url'], isNull);
      },
    );

    test('un serveur qui redémarre reprend les travaux en attente', () async {
      final String jobId = await _requestExport(server, auth, projectId);
      expect((await server.job(jobId))!.status, ExportJobStatus.queued);

      // Un serveur qui redémarre a un worker neuf, et la file porte
      // toujours le travail en attente.
      await server.workerWith().drain();

      final ExportJobRecord? job = await server.job(jobId);
      expect(job!.status, ExportJobStatus.succeeded);
      expect(server.storage.keys, hasLength(1));
    });

    test('journalise la demande dans l\'audit', () async {
      await _requestExport(server, auth, projectId);

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

    test('répond 404 sur le travail d\'un autre compte', () async {
      final String jobId = await _requestExport(server, auth, projectId);

      final http.Response response = await server.get(
        '/v1/exports/$jobId',
        headers: <String, String>{
          'authorization': 'Bearer ${server.tokenFor('user-2')}',
        },
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

/// Demande un export et rend l'identifiant du travail.
Future<String> _requestExport(
  ExportTestServer server,
  Map<String, String> headers,
  String projectId,
) async {
  final http.Response response = await server.post(
    '/v1/export/epub',
    headers: headers,
    body: <String, Object?>{'project_id': projectId},
  );
  expect(response.statusCode, 202);
  return _dataOf(response)['id']! as String;
}

/// La consommation d'exports du compte, dans la période courante.
Future<int> _exportsUsed(ExportTestServer server) {
  return server.quotas.usageOf(
    userId: 'user-1',
    feature: QuotaFeature.exports,
    periodKey: QuotaPeriod.month.keyAt(DateTime.now().toUtc()),
  );
}

/// Le `data` de l'enveloppe d'une réponse.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return payload['data'] as Map<String, dynamic>;
}

/// Le `data` de l'enveloppe d'une réponse qui porte une liste.
List<dynamic> _listOf(http.Response response) {
  final Map<String, dynamic> payload =
      jsonDecode(response.body) as Map<String, dynamic>;
  return payload['data'] as List<dynamic>;
}

/// Crée un projet et rend son identifiant.
Future<String> _createProject(
  ExportTestServer server,
  Map<String, String> headers, [
  String title = 'Manuscrit',
]) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': title},
  );
  return _dataOf(response)['id']! as String;
}

/// Remplit le projet de deux blocs.
Future<void> _pushContent(
  ExportTestServer server,
  Map<String, String> headers,
  String projectId,
) async {
  await server.post(
    '/v1/projects/$projectId/ops',
    headers: headers,
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
}

/// Un stockage qui refuse d'écrire : l'export échoue au moment de ranger
/// l'artefact.
final class _FailingStorage implements ObjectStorage {
  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    throw StateError('The storage refused the object "$key".');
  }

  @override
  Future<String> presignedUrl({
    required String key,
    required Duration expires,
  }) async {
    return 'https://storage.test/$key';
  }
}
