import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_export_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

void main() {
  group('ApiExportRepository', () {
    test('adresse la route du format demandé', () async {
      String? path;
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        return _file();
      });

      await repository.export(
        projectId: 'project-1',
        format: ExportFormat.epub3,
      );

      expect(path, '/v1/export/epub');
    });

    test('envoie l’identifiant du projet', () async {
      Map<String, Object?>? body;
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _file();
      });

      await repository.export(
        projectId: 'project-1',
        format: ExportFormat.pdfReflowable,
      );

      expect(body?['project_id'], 'project-1');
    });

    test('rend le fichier produit par le serveur', () async {
      final ApiExportRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/export/pdf-print');
        return _file();
      });

      final ExportArtefact artefact = await repository.export(
        projectId: 'project-1',
        format: ExportFormat.pdfPrintReady,
      );

      expect(artefact.fileName, 'heures-de-cendre.pdf');
      expect(artefact.mimeType, 'application/pdf');
      expect(artefact.bytes, isA<Uint8List>());
      expect(String.fromCharCodes(artefact.bytes), 'contenu du livre');
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
        return _file();
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

/// Builds the answer of an export.
http.Response _file() => http.Response.bytes(
  Uint8List.fromList('contenu du livre'.codeUnits),
  200,
  headers: <String, String>{
    'content-type': 'application/pdf',
    'content-disposition': 'attachment; filename="heures-de-cendre.pdf"',
  },
);
