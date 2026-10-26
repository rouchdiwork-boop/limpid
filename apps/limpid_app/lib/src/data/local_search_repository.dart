import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/fts_index.dart';
import 'package:limpid_app/src/data/search_query.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// The largest number of passages a search returns.
///
/// The interface shows a list, not a table: a writer never reads more than a
/// few dozen passages, and the index is swept once for the whole list.
const int maxSearchLimit = 200;

/// The search of the manuscript, served by the local database.
///
/// The repository is **local**: it never reaches the network. It answers
/// from the FTS5 index of the device, and the index is brought back in line
/// with the manuscripts before the answer — a passage that was deleted is
/// never offered again.
///
/// The search is **offline by construction**: it works in a plane, in a
/// train, in the middle of nowhere. It is the promise of the product.
final class LocalSearchRepository implements SearchRepository {
  /// Creates a repository on top of [database].
  ///
  /// The account whose manuscripts are searched is resolved on every call:
  /// it follows the session, and a change of account takes effect at once.
  LocalSearchRepository({
    required this.database,
    AuthorId Function()? currentAuthor,
  }) : _currentAuthor =
           currentAuthor ?? (() => AuthorId(database.account.accountId));

  /// The local database of the application.
  final AppDatabase database;

  /// The account whose manuscripts are searched.
  final AuthorId Function() _currentAuthor;

  /// The full-text index of the manuscripts.
  late final FtsIndex _index = FtsIndex(database);

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = defaultSearchLimit,
  }) async {
    final List<String> terms = searchTermsOf(query);
    // Une requête sans mot ne cherche rien : l'index n'est jamais balayé.
    if (terms.isEmpty) return const <SearchResult>[];

    final String accountId = _currentAuthor().value;
    await _index.reconcile(accountId);
    final List<IndexedRow> rows = await _index.rows(
      accountId: accountId,
      match: searchMatchOf(terms),
      limit: limit.clamp(1, maxSearchLimit),
    );
    return List<SearchResult>.unmodifiable(rows.map(_resultOf));
  }

  /// Reads a row of the index as a result.
  SearchResult _resultOf(IndexedRow row) => SearchResult(
    blockId: row.blockId,
    sceneId: row.sceneId,
    sceneTitle: row.sceneTitle,
    projectId: row.projectId,
    projectTitle: row.projectTitle,
    documentId: row.documentId,
    excerpt: row.excerpt,
    highlights: row.highlights,
    relevance: row.relevance,
  );
}
