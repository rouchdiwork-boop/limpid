import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_publication_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/publication/publication_author_books.dart';
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

    test('rend la couverture du livre et les métadonnées publiées', () async {
      final ApiPublicationRepository repository = _repositoryOf(
        (http.Request request) async => _answer(),
      );

      final Publication publication = await repository.load(projectId: bookId);

      final PublishedBook book = publication as PublishedBook;
      expect(
        book.coverUrl,
        'https://api.test/v1/public/books/$bookId/cover',
        reason: 'le serveur adresse la couverture par rapport au livre',
      );
      expect(book.metadata.isbn, '9782491503827');
      expect(book.metadata.language, 'fr-FR');
      expect(book.metadata.priceInCents, 890);
      expect(book.metadata.currency, 'eur');
      expect(book.metadata.contributors, <String>['Aurélien Sandre']);
      expect(book.metadata.categories, <String>['FICTION / Général']);
      expect(book.metadata.publishedAt, DateTime.utc(2026, 10, 2));
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

    test(
      'rend les livres de l’auteur avec leur couverture et leur date',
      () async {
        final ApiPublicationRepository repository = _repositoryOf(
          (http.Request request) async => _authorAnswer(),
        );

        final List<AuthorBook> books = await repository.listShowcaseBooks(
          authorId: 'auteur-1',
        );

        expect(books, hasLength(1));
        expect(
          books.single.coverUrl,
          'https://api.test/v1/public/books/$bookId/cover',
        );
        expect(books.single.publishedAt, DateTime.utc(2026, 10, 2));
      },
    );

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
        'cover': <String, Object?>{'url': '/v1/public/books/$bookId/cover'},
        'metadata': <String, Object?>{
          'isbn': '9782491503827',
          'language': 'fr-FR',
          'contributors': <String>['Aurélien Sandre'],
          'categories': <String>['FICTION / Général'],
          'price': <String, Object?>{'amount': 890, 'currency': 'eur'},
          'publishedAt': '2026-10-02T00:00:00.000Z',
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

/// Builds the answer of the page of an author.
http.Response _authorAnswer() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'books': <Object?>[
          <String, Object?>{
            'id': bookId,
            'title': bookTitle,
            'synopsis': 'Un synopsis.',
            'wordCount': 120,
            'coverUrl': '/v1/public/books/$bookId/cover',
            'publishedAt': '2026-10-02T00:00:00.000Z',
          },
        ],
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
