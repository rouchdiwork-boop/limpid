import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_gdpr_repository.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';

/// The repository of the personal data of the author.
///
/// The server archives the data in a ZIP and renders a signed address: the
/// repository downloads that archive, without the token of the session.
void main() {
  group('ApiGdprRepository', () {
    test('telecharge l archive et rend ses octets', () async {
      final ApiGdprRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        if (request.url.path == '/v1/me/export') {
          return _ok(<String, Object?>{
            'format': 'zip',
            'file_name': 'limpid-donnees-2026-10-26.zip',
            'mime_type': 'application/zip',
            'download_url':
                'https://files.test/account-exports/u-1/archive.zip',
            'expires_in_seconds': 900,
            'exported_at': '2026-10-26T09:00:00.000Z',
            'counts': <String, Object?>{'projects': 3, 'documents': 7},
          });
        }
        expect(request.url.toString(), contains('archive.zip'));
        return http.Response.bytes(<int>[0x50, 0x4b, 0x03, 0x04, 0x00], 200);
      });

      final PersonalDataExport export = await repository.exportPersonalData();

      expect(export.fileName, 'limpid-donnees-2026-10-26.zip');
      expect(export.mimeType, 'application/zip');
      expect(export.bytes, <int>[0x50, 0x4b, 0x03, 0x04, 0x00]);
      expect(export.generatedAt, DateTime.utc(2026, 10, 26, 9));
      expect(export.projectCount, 3);
    });

    test('ne porte ni le jeton ni la preuve a l hote du fichier', () async {
      // L'URL signee porte sa propre autorisation : lui envoyer le jeton
      // de session le divulguerait a l'hote du stockage objet.
      final ApiGdprRepository repository = _repositoryOf(
        (http.Request request) async {
          if (request.url.path == '/v1/me/export') {
            return _ok(<String, Object?>{
              'file_name': 'limpid-donnees.zip',
              'mime_type': 'application/zip',
              'download_url': 'https://files.test/archive.zip',
              'exported_at': '2026-10-26T09:00:00.000Z',
              'counts': <String, Object?>{'projects': 0},
            });
          }
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('x-limpid-2fa'), isFalse);
          return http.Response.bytes(<int>[0x50, 0x4b], 200);
        },
        token: 'session-token',
        twoFactorProof: 'proof-1',
      );

      await repository.exportPersonalData();
    });

    test('refuse une reponse sans adresse de telechargement', () async {
      final ApiGdprRepository repository = _repositoryOf(
        (http.Request request) async =>
            _ok(<String, Object?>{'file_name': 'x.zip'}),
      );

      await expectLater(
        repository.exportPersonalData(),
        throwsA(isA<Exception>()),
      );
    });

    test('demande la suppression du compte', () async {
      final ApiGdprRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/me');
        return _ok(<String, Object?>{
          'requested_at': '2026-10-26T09:00:00.000Z',
          'scheduled_for': '2026-11-25T09:00:00.000Z',
          'retention_days': 30,
        });
      });

      final AccountDeletion deletion = await repository
          .requestAccountDeletion();

      expect(deletion.requestedAt, DateTime.utc(2026, 10, 26, 9));
      expect(deletion.scheduledFor, DateTime.utc(2026, 11, 25, 9));
      expect(deletion.retentionDays, 30);
    });
  });
}

/// Builds a repository talking to a fake server.
ApiGdprRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler, {
  String? token,
  String? twoFactorProof,
}) => ApiGdprRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
    tokenProvider: () async => token,
    twoFactorProof: () => twoFactorProof,
  ),
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);
