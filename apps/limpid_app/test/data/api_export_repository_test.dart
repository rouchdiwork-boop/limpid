import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_export_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/export_repository.dart';
import 'package:limpid_core/limpid_core.dart';

void main() {
  group('ApiExportRepository', () {
    test('adresse la route du format demandé', () async {
      final List<String> paths = <String>[];
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        paths.add(request.url.path);
        return _job(status: 'succeeded');
      });

      await repository.export(
        projectId: 'project-1',
        format: ExportFormat.epub3,
      );

      expect(paths.first, '/v1/export/epub');
    });

    test('envoie l’identifiant du projet', () async {
      Map<String, Object?>? body;
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        if (request.method == 'POST') {
          final Object? decoded = jsonDecode(request.body);
          body = decoded is Map<String, Object?> ? decoded : null;
        }
        return _job(status: 'succeeded');
      });

      await repository.export(
        projectId: 'project-1',
        format: ExportFormat.pdfReflowable,
      );

      expect(body?['project_id'], 'project-1');
    });

    test('suit le travail et rend le fichier produit', () async {
      final List<String> paths = <String>[];
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        paths.add(request.url.path);
        if (request.url.host == 'storage.test') return _file();
        return _job(status: 'succeeded');
      });

      final ExportArtefact artefact = await repository.export(
        projectId: 'project-1',
        format: ExportFormat.pdfPrintReady,
      );

      expect(paths, contains('/v1/exports/job-1'));
      expect(artefact.fileName, 'heures-de-cendre.pdf');
      expect(artefact.mimeType, 'application/pdf');
      expect(String.fromCharCodes(artefact.bytes), 'contenu du livre');
    });

    test('demande le travail et rend son état', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return _job(status: 'queued');
      });

      final ExportProgress progress = await repository.start(
        projectId: 'project-1',
        format: ExportFormat.epub3,
      );

      expect(progress, isA<ExportQueued>());
      expect(progress.id, 'job-1');
    });

    test('lit un travail prêt et son adresse', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return _job(status: 'succeeded');
      });

      final ExportProgress progress = await repository.read('job-1');

      expect(progress, isA<ExportReady>());
      final ExportReady ready = progress as ExportReady;
      expect(ready.downloadUrl.toString(), contains('storage.test'));
      expect(ready.expiresAt, isNotNull);
      expect(ready.fileName, 'heures-de-cendre.pdf');
    });

    test('lit un travail en échec et son message', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'id': 'job-1',
              'status': 'failed',
              'error': 'L’export n’a pas pu être généré.',
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final ExportProgress progress = await repository.read('job-1');

      expect(progress, isA<ExportFailed>());
      expect(
        (progress as ExportFailed).message,
        'L’export n’a pas pu être généré.',
      );
    });

    test('relance un travail et rend le travail neuf', () async {
      String? path;
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{'id': 'job-2', 'status': 'queued'},
          }),
          202,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final ExportProgress progress = await repository.retry('job-1');

      expect(path, '/v1/exports/job-1/retry');
      expect(progress.id, 'job-2');
    });

    test('remonte une erreur typée quand le serveur refuse l’export', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'conflict',
              'message': 'Ce projet n’a encore aucun contenu à exporter.',
            },
          }),
          409,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      await expectLater(
        repository.export(
          projectId: 'project-1',
          format: ExportFormat.markdown,
        ),
        throwsA(
          isA<ApiValidationException>().having(
            (ApiValidationException e) => e.message,
            'message',
            'Ce projet n’a encore aucun contenu à exporter.',
          ),
        ),
      );
    });

    test('refuse un format que l’API ne produit pas', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return _job(status: 'queued');
      });

      await expectLater(
        repository.export(
          projectId: 'project-1',
          format: ExportFormat.kindleKpf,
        ),
        throwsA(isA<ApiValidationException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiExportRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiExportRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds the answer of a job.
http.Response _job({required String status}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'id': 'job-1',
        'status': status,
        'project_id': 'project-1',
        'format': 'epub3',
        'error': status == 'failed' ? 'L’export a échoué.' : null,
        'download_url': status == 'succeeded'
            ? 'https://storage.test/exports/project-1/heures-de-cendre.pdf'
            : null,
        'file_name': status == 'succeeded' ? 'heures-de-cendre.pdf' : null,
        'expires_at': status == 'succeeded' ? '2026-10-26T10:15:00.000Z' : null,
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// Builds the answer of the downloaded file.
http.Response _file() => http.Response.bytes(
  Uint8List.fromList('contenu du livre'.codeUnits),
  200,
  headers: <String, String>{
    'content-type': 'application/pdf',
    'content-disposition': 'attachment; filename="heures-de-cendre.pdf"',
  },
);
