import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/data/local_publication_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// The author of a book read on the showcase.
///
/// The public page never carries the owner of a book: the model of the
/// manuscript needs an author, and the showcase borrows a neutral one.
const AuthorId kPublicBookAuthorId = AuthorId('public-book');

/// The largest number of characters an excerpt keeps.
///
/// The public page shows an excerpt, never the whole text of a scene: a
/// reader who wants the book buys it. The server applies the very same rule
/// (`apps/limpid_api/lib/src/routes/publication_routes.dart`), so the page of
/// the server and the page of the device show the same excerpt.
const int maxExcerptLength = 320;

/// The character appended to a truncated excerpt.
const String excerptEllipsis = '…';

/// The excerpt of a scene: its first paragraph.
///
/// The excerpt is read from the CRDT document of the scene. The tombstones
/// are ignored — a deleted block is not part of the manuscript any more — and
/// a scene that was never written has no excerpt at all.
String excerptOf(CrdtDocument document) {
  for (final Block block in document.blocks) {
    if (block.deleted) continue;
    if (block.type != BlockType.paragraph) continue;
    final String text = block.content.plainText.trim();
    if (text.isEmpty) continue;
    return truncateExcerpt(text);
  }
  return '';
}

/// Shortens an excerpt to [maxExcerptLength] characters.
///
/// The cut falls on a word boundary, so that a reader never reads a word cut
/// in half.
String truncateExcerpt(String text) {
  if (text.length <= maxExcerptLength) return text;
  final int boundary = text.lastIndexOf(' ', maxExcerptLength);
  final int end = boundary > 0 ? boundary : maxExcerptLength;
  return '${text.substring(0, end).trimRight()}$excerptEllipsis';
}

/// A scene of a published book, reduced to what a reader may see.
///
/// The public page never carries the whole text of a scene: it carries its
/// excerpt, its title and its number of words. The rest of the manuscript
/// stays on the device of the author.
@immutable
final class PublicationScene {
  /// Creates a scene of a published book.
  const PublicationScene({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.wordCount,
  });

  /// Identifier of the scene.
  final SceneId id;

  /// Title of the scene.
  final String title;

  /// The first paragraph of the scene, empty when the scene was never
  /// written.
  final String excerpt;

  /// Number of words written in the scene.
  final int wordCount;

  /// Whether the scene carries an excerpt.
  bool get hasExcerpt => excerpt.isNotEmpty;
}

/// A chapter of a published book, with the scenes a reader may read.
@immutable
final class PublicationChapter {
  /// Creates a chapter of a published book.
  const PublicationChapter({
    required this.id,
    required this.title,
    required this.synopsis,
    required this.scenes,
  });

  /// Identifier of the chapter.
  final ChapterId id;

  /// Title of the chapter.
  final String title;

  /// Short synopsis of the chapter.
  final String synopsis;

  /// The scenes of the chapter, in reading order.
  final List<PublicationScene> scenes;

  /// The number of words the scenes of the chapter hold.
  int get wordCount => scenes.fold<int>(
    0,
    (int total, PublicationScene scene) => total + scene.wordCount,
  );
}

/// The public page of a book.
///
/// The page exists only for a published book: the state of the manuscript
/// decides whether a reader may see it, never the interface alone.
@immutable
sealed class Publication {
  /// Creates a publication.
  const Publication();
}

/// A book that is published: its public page exists.
final class PublishedBook extends Publication {
  /// Creates a published book.
  const PublishedBook({
    required this.project,
    required this.chapters,
    this.coverUrl = '',
    this.metadata = const PublicationMetadata(),
  });

  /// The manuscript behind the page.
  final Project project;

  /// The chapters of the book, in reading order.
  final List<PublicationChapter> chapters;

  /// The address of the cover of the book, empty when the book has none.
  ///
  /// The address is the one of the server: the cover is an artefact, and
  /// the page never draws a broken image in its place.
  final String coverUrl;

  /// The commercial metadata the author published.
  final PublicationMetadata metadata;

  /// The number of words the chapters of the book hold.
  int get wordCount => chapters.fold<int>(
    0,
    (int total, PublicationChapter chapter) => total + chapter.wordCount,
  );
}

/// The commercial metadata an author published for a book.
///
/// The metadata come from the server: they are the ones that were
/// published, and they make fi. A metadata the author did not publish has
/// no line on the page — the page shows what was said, and nothing else.
@immutable
final class PublicationMetadata {
  /// Creates a set of published metadata.
  const PublicationMetadata({
    this.isbn = '',
    this.publisher = '',
    this.description = '',
    this.language = '',
    this.contributors = const <String>[],
    this.keywords = const <String>[],
    this.categories = const <String>[],
    this.priceInCents,
    this.currency = '',
    this.publishedAt,
  });

  /// The ISBN of the published edition.
  final String isbn;

  /// The publisher of the book.
  final String publisher;

  /// The public description of the book.
  final String description;

  /// The language of the book.
  final String language;

  /// The people who wrote the book.
  final List<String> contributors;

  /// The keywords of the product page.
  final List<String> keywords;

  /// The BISAC categories of the product page.
  final List<String> categories;

  /// The price of the book, in cents, `null` when the book is not for sale.
  final int? priceInCents;

  /// The currency of the price.
  final String currency;

  /// The date the book was published.
  final DateTime? publishedAt;

  /// Whether the book published nothing.
  bool get isEmpty =>
      isbn.isEmpty &&
      publisher.isEmpty &&
      description.isEmpty &&
      language.isEmpty &&
      contributors.isEmpty &&
      keywords.isEmpty &&
      categories.isEmpty &&
      priceInCents == null &&
      publishedAt == null;
}

/// A book that exists but is not published yet: it has no public page.
final class UnpublishedBook extends Publication {
  /// Creates an unpublished book.
  const UnpublishedBook({required this.project});

  /// The manuscript behind the missing page.
  final Project project;
}

/// A project that does not exist: it has no public page.
final class UnknownBook extends Publication {
  /// Creates an unknown book.
  const UnknownBook({required this.projectId});

  /// The identifier that was asked for.
  final String projectId;
}

/// The public page of a book.
///
/// The contract is deliberately **two sources**: the implementation reads the
/// API, and the local database is its fallback. The application is offline
/// first — a network failure must degrade to the local page, never to an
/// error screen — and the page of a book must open on a device that has no
/// network at all.
///
/// The implementation lives in `lib/src/data/`.
abstract interface class PublicationRepository {
  /// The public page of the book of [projectId].
  ///
  /// The answer is never an error the interface has to show: a book that is
  /// not published has no page, and the page of the local manuscript is
  /// served when the server cannot be reached.
  Future<Publication> load({required String projectId});
}

/// The repository serving the public page of the books.
///
/// The composition root overrides it with the implementation that reads the
/// API. The default reads the local database: the page of a book opens even
/// without a network, and the application never shows an error screen for a
/// page a reader may read.
final Provider<PublicationRepository> publicationRepositoryProvider =
    Provider<PublicationRepository>((Ref ref) {
      return LocalPublicationRepository(
        manuscript: ref.watch(manuscriptRepositoryProvider),
      );
    });
