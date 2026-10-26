import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/publication/publication_author_books.dart';
import 'package:limpid_core/limpid_core.dart';

/// The public page of a book, served by the API.
///
/// The showcase of the server is the public catalogue of the published
/// books: `GET /v1/public/books/<projectId>` answers the book of a reader
/// who has no account and no local manuscript.
///
/// The repository never leaves the reader without a page: when the server
/// publishes no page — the book is unknown, it is not published or it is not
/// public — or when it cannot be reached at all, the local manuscript takes
/// over. The application is offline first: a network failure degrades to the
/// local page, never to an error screen.
final class ApiPublicationRepository
    implements PublicationRepository, AuthorBooksPort {
  /// Creates a repository on top of [client].
  const ApiPublicationRepository({
    required this.client,
    required this.fallback,
  });

  /// The client of the API.
  final ApiClient client;

  /// The repository serving the page when the API publishes none.
  final PublicationRepository fallback;

  @override
  Future<Publication> load({required String projectId}) async {
    final Publication? published = await _publishedBy(projectId);
    if (published != null) return published;
    return fallback.load(projectId: projectId);
  }

  /// The book the server publishes, `null` when it publishes none.
  ///
  /// A network failure and a missing page are the two answers that send the
  /// reader back to the local manuscript. A malformed answer is not: it is a
  /// bug of the server, and it must be visible.
  Future<Publication?> _publishedBy(String projectId) async {
    try {
      final Object? payload = await client.get(
        '/v1/public/books/${Uri.encodeComponent(projectId)}',
      );
      return _bookOf(payload);
    } on ApiNotFoundException {
      return null;
    } on ApiNetworkException {
      return null;
    } on ApiTimeoutException {
      return null;
    }
  }

  /// The book carried by the payload of the API.
  Publication _bookOf(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the book of the showcase.',
      );
    }
    return PublishedBook(
      project: _projectOf(payload['project']),
      chapters: List<PublicationChapter>.unmodifiable(
        _chaptersOf(payload['chapters']),
      ),
    );
  }

  /// The manuscript behind the published book.
  ///
  /// The owner of the book never leaves the server: the model needs an
  /// author, and the page borrows a neutral one.
  Project _projectOf(Object? raw) {
    final Map<String, Object?> json = _objectOf(raw, 'project');
    return Project(
      id: ProjectId(_identifierOf(json, 'id')),
      ownerId: kPublicBookAuthorId,
      title: _textOf(json, 'title'),
      synopsis: _textOf(json, 'synopsis'),
      status: ManuscriptStatus.published,
      order: OrderKey.initial,
    );
  }

  /// The chapters of the published book.
  List<PublicationChapter> _chaptersOf(Object? raw) {
    if (raw is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the chapters of the book.',
      );
    }
    return raw.map(_chapterOf).toList(growable: false);
  }

  /// A chapter of the published book.
  PublicationChapter _chapterOf(Object? raw) {
    final Map<String, Object?> json = _objectOf(raw, 'chapter');
    return PublicationChapter(
      id: ChapterId(_identifierOf(json, 'id')),
      title: _textOf(json, 'title'),
      synopsis: _textOf(json, 'synopsis'),
      scenes: List<PublicationScene>.unmodifiable(_scenesOf(json['scenes'])),
    );
  }

  /// The scenes of a chapter of the published book.
  List<PublicationScene> _scenesOf(Object? raw) {
    if (raw is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the scenes of the chapter.',
      );
    }
    return raw.map(_sceneOf).toList(growable: false);
  }

  /// A scene of the published book: its title, its excerpt and its length.
  PublicationScene _sceneOf(Object? raw) {
    final Map<String, Object?> json = _objectOf(raw, 'scene');
    return PublicationScene(
      id: SceneId(_identifierOf(json, 'id')),
      title: _textOf(json, 'title'),
      excerpt: _textOf(json, 'excerpt'),
      wordCount: _wordCountOf(json),
    );
  }

  /// The books the server publishes for the author [authorId].
  ///
  /// The answer is never an error the interface has to show: an author who
  /// publishes no book has an empty list, and so does an unreachable server.
  @override
  Future<List<AuthorBook>> listShowcaseBooks({required String authorId}) async {
    try {
      final Object? payload = await client.get(
        '/v1/public/authors/${Uri.encodeComponent(authorId)}',
      );
      return _authorBooksOf(payload);
    } on ApiNotFoundException {
      return const <AuthorBook>[];
    } on ApiNetworkException {
      return const <AuthorBook>[];
    } on ApiTimeoutException {
      return const <AuthorBook>[];
    }
  }

  /// The books carried by the payload of the API.
  List<AuthorBook> _authorBooksOf(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the books of the author.',
      );
    }
    final Object? books = payload['books'];
    if (books is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the books of the author.',
      );
    }
    return books.map(_authorBookOf).toList(growable: false);
  }

  /// The book carried by one entry of the payload.
  AuthorBook _authorBookOf(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return a book of the author.',
      );
    }
    return AuthorBook(
      id: _identifierOf(raw, 'id'),
      title: _textOf(raw, 'title'),
      synopsis: _textOf(raw, 'synopsis'),
      wordCount: _wordCountOf(raw),
    );
  }

  /// Reads a JSON object, or refuses the answer.
  Map<String, Object?> _objectOf(Object? raw, String what) {
    if (raw is! Map<String, Object?>) {
      throw ApiMalformedResponseException(
        'The API did not return the $what of the book.',
      );
    }
    return raw;
  }

  /// Reads an identifier, or refuses the answer.
  String _identifierOf(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is! String || value.isEmpty) {
      throw ApiMalformedResponseException(
        'The API did not return the "$field" of the book.',
      );
    }
    return value;
  }

  /// Reads a text, an empty string when the server sends none.
  String _textOf(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    return value is String ? value : '';
  }

  /// Reads the number of words of a scene, zero when the server sends none.
  int _wordCountOf(Map<String, Object?> json) {
    final Object? value = json['wordCount'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const ApiMalformedResponseException(
      'The API did not return the number of words of the scene.',
    );
  }
}
