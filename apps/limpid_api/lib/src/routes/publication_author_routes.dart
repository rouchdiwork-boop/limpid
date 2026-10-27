import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/book_sale_store.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../middleware/rate_limiter.dart';
import 'publication_cover.dart';
import 'publication_routes.dart';

/// La route de la page publique d'un auteur.
const String publicAuthorRoute = '/v1/public/authors/<authorId>';

/// Le préfixe des pages publiques des auteurs.
const String publicAuthorRoutePrefix = '/v1/public/authors/';

/// Le nombre de pages d'auteur qu'une adresse IP peut envoyer d'un coup.
const int publicAuthorRateLimitCapacity = 60;

/// Le nombre de pages d'auteur qu'une adresse IP récupère par seconde.
const double publicAuthorRateLimitRefillPerSecond = 2;

/// Le nombre maximal de livres que la page d'un auteur liste.
///
/// La page est un catalogue : elle liste les livres publiés de l'auteur, les
/// plus récents d'abord. La limite suit celle des pages du serveur
/// (ARCHITECTURE.md §6.1).
const int maxPublicBooksPerAuthor = 200;

/// Enregistre la route de la page publique d'un auteur.
///
/// La page ne porte aucun jeton : elle est lue par un visiteur qui n'a pas
/// de compte, comme la vitrine d'un livre. Elle répond le même `404` pour un
/// auteur qui n'existe pas et pour un auteur qui ne publie aucun livre : la
/// vitrine ne doit jamais révéler l'existence d'un manuscrit privé.
///
/// La route a son propre seau de débit : elle lit le journal de chaque livre
/// publié de l'auteur, et elle ne doit pas voler le quota de la vitrine
/// d'un livre.
void registerPublicationAuthorRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: publicAuthorRateLimitCapacity,
    refillPerSecond: publicAuthorRateLimitRefillPerSecond,
  );
  final Middleware limit = rateLimitMiddleware(
    limiter: limiter,
    scope: 'public_author',
    applies: (Request request) =>
        request.requestedUri.path.startsWith(publicAuthorRoutePrefix),
  );

  router.get(publicAuthorRoute, (Request request, String authorId) {
    return limit((Request request) => _serveAuthor(dependencies, authorId))(
      request,
    );
  });
}

/// Sert la page publique d'un auteur.
///
/// Les livres listés sont ceux que la base déclare publiés et publics : le
/// prédicat est appliqué **avant** toute lecture du journal, donc un livre
/// privé ne coûte jamais le chargement d'un manuscrit.
Future<Response> _serveAuthor(
  AppDependencies dependencies,
  String authorId,
) async {
  final List<ProjectRecord> books = await _publishedBooks(
    dependencies,
    authorId,
  );
  if (books.isEmpty) {
    // Les deux refusals — auteur absent, auteur qui ne publie aucun livre —
    // répondent le même 404 : la vitrine ne divulgue jamais l'existence d'un
    // manuscrit privé.
    throw const NotFoundException();
  }

  final Map<String, DateTime> publishedAt = await _publicationDates(
    dependencies,
    authorId,
  );
  final List<ProjectRecord> ordered = _byPublication(books, publishedAt);

  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
  for (final ProjectRecord book in ordered) {
    entries.add(await _bookJson(dependencies, book, publishedAt[book.id]));
  }

  return ApiResponse.ok(<String, Object?>{'books': entries});
}

/// Les livres publiés et publics de l'auteur.
///
/// Le prédicat est appliqué **par la base** : `findPublic` ne répond un
/// livre que s'il est publié (`status = 'published'`), public
/// (`is_public = TRUE`) et vivant (`deleted_at IS NULL`). Un livre privé
/// n'est donc jamais chargé, et le journal d'un livre privé n'est jamais lu.
Future<List<ProjectRecord>> _publishedBooks(
  AppDependencies dependencies,
  String authorId,
) async {
  final ProjectPage page = await dependencies.projects.list(
    userId: authorId,
    limit: maxPublicBooksPerAuthor,
    cursor: null,
  );

  final List<ProjectRecord> published = <ProjectRecord>[];
  for (final ProjectRecord candidate in page.items) {
    // La page est celle de l'auteur : un livre qu'il relit sans le posséder
    // n'est pas le sien.
    if (candidate.ownerId != authorId) continue;
    final ProjectRecord? book = await dependencies.projects.findPublic(
      projectId: candidate.id,
    );
    if (book != null) published.add(book);
  }
  return published;
}

/// Les dates de publication des livres de l'auteur.
///
/// La date est celle de la **mise en vente** du livre : c'est l'acte qui
/// publie le livre, et il ne bouge plus. Une republication garde la première
/// date : l'ordre de la page ne change pas quand l'auteur repasse son
/// livre en vente.
///
/// Un serveur qui ne tient pas les ventes ne date aucun livre : les livres
/// viennent alors après les autres, et la page reste lisible.
Future<Map<String, DateTime>> _publicationDates(
  AppDependencies dependencies,
  String authorId,
) async {
  final BookSaleStore? sales = dependencies.bookSales;
  if (sales == null) return const <String, DateTime>{};
  final List<BookSaleRecord> records = await sales.listByOwner(authorId);
  final Map<String, DateTime> dates = <String, DateTime>{};
  for (final BookSaleRecord record in records) {
    final DateTime? publishedAt = record.publishedAt;
    if (publishedAt == null) continue;
    final DateTime? known = dates[record.projectId];
    if (known == null || publishedAt.isBefore(known)) {
      dates[record.projectId] = publishedAt;
    }
  }
  return dates;
}

/// Les livres de l'auteur, du plus récemment publié au plus ancien.
///
/// L'ordre est celui de la **publication** : un livre publié plus tard passe
/// devant un livre publié plus tôt, et un livre qui n'a jamais été publié
/// vient après les autres. Modifier un livre ne change pas cet ordre : c'est
/// la publication qui place le livre.
List<ProjectRecord> _byPublication(
  List<ProjectRecord> books,
  Map<String, DateTime> publishedAt,
) {
  final List<ProjectRecord> ordered = List<ProjectRecord>.of(books);
  ordered.sort((ProjectRecord left, ProjectRecord right) {
    final DateTime? leftDate = publishedAt[left.id];
    final DateTime? rightDate = publishedAt[right.id];
    if (leftDate != null && rightDate != null) {
      final int byDate = rightDate.compareTo(leftDate);
      if (byDate != 0) return byDate;
      return left.id.compareTo(right.id);
    }
    if (leftDate != null) return -1;
    if (rightDate != null) return 1;
    return left.id.compareTo(right.id);
  });
  return List<ProjectRecord>.unmodifiable(ordered);
}

/// La partie publique d'un livre : son titre, son résumé et sa longueur.
///
/// Le propriétaire, les membres, l'étape du manuscrit et le texte des scènes
/// restent sur le serveur : un lecteur n'en a pas l'usage, et ils en
/// diraient plus long sur l'auteur que sur le livre.
Future<Map<String, Object?>> _bookJson(
  AppDependencies dependencies,
  ProjectRecord book,
  DateTime? publishedAt,
) async {
  final int words = await publicWordCountOf(dependencies, book.id);
  return <String, Object?>{
    'id': book.id,
    'title': book.title,
    'synopsis': book.synopsis,
    'wordCount': words,
    'coverUrl': publicCoverUrlOf(book.id),
    if (publishedAt != null)
      'publishedAt': publishedAt.toUtc().toIso8601String(),
  };
}
