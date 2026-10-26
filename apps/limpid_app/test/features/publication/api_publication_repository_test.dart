import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_publication_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_core/limpid_core.dart';

import 'fakes.dart';

/// The identifier of the book of the tests.
const String bookId = 'heures';

/// The title of the book of the tests.
const String bookTitle = 'Les Heures de Cendre';

/// The excerpt of the first scene of the book.
const String sceneExcerpt = 'La cloche sonna à quatre heures douze.';

void main() {
  group('ApiPublicationRepository', () {
    test('adresse la route publique du livre', () async {
      String? path;
      final ApiPublicationRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        return _answer();
      });

      await repository.load(projectId: bookId);

      expect(path, '/v1/public/books/$bookId');
    });

    test('rend le livre publié par le serveur', () async {
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => _answer(),
      );

      final Publication publication = await repository.load(projectId: bookId);

      expect(publication, isA<PublishedBook>());
      final PublishedBook book = publication as PublishedBook;
      expect(book.project.id.value, bookId);
      expect(book.project.title, bookTitle);
      expect(book.project.synopsis, 'Un synopsis.');
      expect(book.project.status, ManuscriptStatus.published);
      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.scenes, hasLength(1));
      expect(book.chapters.single.scenes.single.excerpt, sceneExcerpt);
      expect(book.chapters.single.scenes.single.wordCount, 120);
    });

    test('n-emprunte jamais le propriétaire du livre au serveur', () async {
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => _answer(),
      );

      final Publication publication = await repository.load(projectId: bookId);

      final PublishedBook book = publication as PublishedBook;
      expect(book.project.ownerId, kPublicBookAuthorId);
    });

    test('reprend la page locale quand le serveur ne publie rien', () async {
      final FakePublicationPageRepository fallback =
          FakePublicationPageRepository(
            publication: PublishedBook(
              project: _project(),
              chapters: const <PublicationChapter>[],
            ),
          );
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'not_found',
              'message': "Cette ressource n'existe pas.",
            },
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        ),
        fallback: fallback,
      );

      final Publication publication = await repository.load(projectId: bookId);

      expect(publication, isA<PublishedBook>());
      expect(fallback.calls, 1);
    });

    test('reprend la page locale quand le serveur est injoignable', () async {
      final FakePublicationPageRepository fallback =
          FakePublicationPageRepository(
            publication: PublishedBook(
              project: _project(),
              chapters: const <PublicationChapter>[],
            ),
          );
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async =>
            throw http.ClientException('the API is unreachable'),
        fallback: fallback,
      );

      final Publication publication = await repository.load(projectId: bookId);

      expect(publication, isA<PublishedBook>());
      expect(fallback.calls, 1);
    });

    test('refuse une réponse qui n’est pas un livre', () async {
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{'book': 42},
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.load(projectId: bookId),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });

    test('refuse une réponse qui n’est pas du JSON', () async {
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => http.Response('pas du json', 200),
      );

      await expectLater(
        repository.load(projectId: bookId),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiPublicationRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler, {
  PublicationRepository? fallback,
}) {
  return ApiPublicationRepository(
    client: ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient(handler),
    ),
    fallback: fallback ?? FakePublicationPageRepository(),
  );
}

/// Builds the answer of the showcase.
http.Response _answer() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'project': <String, Object?>{
          'id': bookId,
          'title': bookTitle,
          'synopsis': 'Un synopsis.',
          'language': 'fr-FR',
        },
        'chapters': <Object?>[
          <String, Object?>{
            'id': bookId,
            'title': bookTitle,
            'synopsis': '',
            'scenes': <Object?>[
              <String, Object?>{
                'id': 'scene-1',
                'title': "L'aube",
                'excerpt': sceneExcerpt,
                'wordCount': 120,
              },
            ],
          },
        ],
        'wordCount': 120,
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// Builds the manuscript of the book of the tests.
Project _project() {
  return const Project(
    id: ProjectId(bookId),
    ownerId: kPublicBookAuthorId,
    title: bookTitle,
    synopsis: 'Un synopsis.',
    status: ManuscriptStatus.published,
    order: OrderKey.initial,
  );
}
