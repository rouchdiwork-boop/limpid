import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_kdp_repository.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';

import 'fakes.dart';

void main() {
  group('ApiKdpRepository', () {
    test('liste les dépôts du compte avec leur état', () async {
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/publishing/kdp');
        return _ok(<Object?>[
          _publication(
            id: 'pub_1',
            status: 'ready',
            issues: <Object?>[
              <String, Object?>{
                'code': 'isbn_missing',
                'field': 'isbn',
                'message': "L'édition imprimée exige un ISBN.",
                'severity': 'blocking',
              },
            ],
          ),
          _publication(id: 'pub_2', status: 'blocked'),
        ]);
      });

      final List<KdpSubmission> submissions = await repository.list();

      expect(submissions, hasLength(2));
      expect(submissions.first.id, 'pub_1');
      expect(submissions.first.state, KdpState.draft);
      expect(submissions.first.isReady, isTrue);
      expect(submissions.first.issues, hasLength(1));
      expect(submissions.last.isReady, isFalse);
      expect(submissions.last.title, 'Les Heures de Cendre');
    });

    test('lit un dépôt', () async {
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/publishing/kdp/pub_1');
        return _ok(_publication(id: 'pub_1'));
      });

      final KdpSubmission? submission = await repository.find('pub_1');

      expect(submission, isNotNull);
      expect(submission?.id, 'pub_1');
      expect(submission?.isbn, fakeIsbn);
    });

    test('prépare un dossier avec ses métadonnées', () async {
      Map<String, Object?>? body;
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/publishing/kdp');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(_publication(id: 'pub_9'), status: 201);
      });

      final KdpSubmission submission = await repository.prepare(
        projectId: 'project_1',
        metadata: fakeMetadata.copyWith(subtitle: 'Le premier jour'),
      );

      expect(body?['project_id'], 'project_1');
      // Le serveur ne garde qu'un titre : le sous-titre y est joint.
      expect(body?['title'], 'Les Heures de Cendre: Le premier jour');
      expect(body?['author'], 'Camille Martin');
      expect(body?['isbn'], fakeIsbn);
      expect(body?['keywords'], <String>['archives', 'mystère']);
      expect(body?['categories'], <String>['Roman historique']);
      expect(submission.id, 'pub_9');
    });

    test('refuse un ISBN mal formé avant d’envoyer', () async {
      bool called = false;
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        called = true;
        return _ok(_publication());
      });

      await expectLater(
        repository.prepare(
          projectId: 'project_1',
          metadata: fakeMetadata.copyWith(isbn: '1234567890'),
        ),
        throwsA(isA<KdpValidationException>()),
      );
      expect(called, isFalse);
    });

    test('dépose un dossier et rend le verdict d’Amazon', () async {
      final List<String> paths = <String>[];
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/deposits')) {
          return _ok(<String, Object?>{
            'id': 'dep_1',
            'publication_id': 'pub_1',
            'status': 'submitted',
            'amazon_submission_id': 'amazon-1',
            'issues': <Object?>[],
            'failure_reason': null,
            'attempts': 1,
            'created_at': '2026-10-25T10:00:00.000Z',
            'updated_at': '2026-10-25T10:00:01.000Z',
          });
        }
        return _ok(_publication(id: 'pub_1'));
      });

      final KdpSubmission submission = await repository.deposit(
        submissionId: 'pub_1',
      );

      expect(paths, <String>[
        '/v1/publishing/kdp/deposits',
        '/v1/publishing/kdp/pub_1',
      ]);
      expect(submission.state, KdpState.submitted);
      expect(submission.depositId, 'dep_1');
      expect(submission.amazonSubmissionId, 'amazon-1');
      expect(submission.refusal, isNull);
    });

    test('un refus d’Amazon porte son motif', () async {
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        if (request.url.path.endsWith('/deposits')) {
          return _ok(<String, Object?>{
            'id': 'dep_1',
            'publication_id': 'pub_1',
            'status': 'rejected',
            'amazon_submission_id': null,
            'issues': <Object?>[
              <String, Object?>{
                'code': 'isbn_already_in_use',
                'field': 'isbn',
                'message':
                    "L'ISBN indiqué est déjà utilisé par un autre ouvrage.",
                'severity': 'blocking',
              },
            ],
            'failure_reason': null,
            'attempts': 1,
            'updated_at': '2026-10-25T10:00:01.000Z',
          });
        }
        return _ok(_publication(id: 'pub_1'));
      });

      final KdpSubmission submission = await repository.deposit(
        submissionId: 'pub_1',
      );

      expect(submission.state, KdpState.refused);
      expect(submission.refusal, isNotNull);
      expect(submission.refusal?.issues, hasLength(1));
      expect(submission.refusal?.issues.first.field, 'isbn');
      expect(submission.refusal?.issues.first.message, contains('ISBN'));
    });

    test('un dépôt impossible sur ce poste est dit', () async {
      final ApiKdpRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'service_unavailable',
              'message':
                  "La distribution Amazon KDP n'est pas configurée sur ce "
                  'serveur.',
              'details': <String, Object?>{},
            },
          }),
          503,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      await expectLater(
        repository.deposit(submissionId: 'pub_1'),
        throwsA(
          isA<KdpUnavailableException>().having(
            (KdpUnavailableException error) => error.reason,
            'reason',
            contains('Amazon KDP'),
          ),
        ),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiKdpRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiKdpRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data, {int status = 200}) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Builds the publication the server answers.
Map<String, Object?> _publication({
  String id = 'pub_1',
  String status = 'ready',
  List<Object?> issues = const <Object?>[],
}) {
  return <String, Object?>{
    'id': id,
    'project_id': 'project_1',
    'user_id': 'user_1',
    'title': 'Les Heures de Cendre',
    'author': 'Camille Martin',
    'description': 'Une archiviste et une cloche.',
    'keywords': <String>['archives', 'mystère'],
    'categories': <String>['Roman historique'],
    'isbn': fakeIsbn,
    'language': 'fr',
    'publisher': 'Atelier Sandre',
    'status': status,
    'word_count': 48210,
    'page_count': 212,
    'manuscript_version': '2026-10-20T08:00:00.000Z',
    'created_at': '2026-10-20T08:00:00.000Z',
    'issues': issues,
  };
}
