import 'package:flutter/foundation.dart';

/// The passage of a manuscript found by a search.
///
/// The result carries everything the interface needs to show the passage and
/// to go to it: the scene it belongs to, the excerpt around the passage, and
/// the identifier of the block that carries it.
///
/// The object is immutable: a result is never modified, it is replaced.
@immutable
final class SearchResult {
  /// Creates a result.
  const SearchResult({
    required this.blockId,
    required this.sceneId,
    required this.sceneTitle,
    required this.projectId,
    required this.projectTitle,
    required this.documentId,
    required this.excerpt,
    this.highlights = const <SearchHighlight>[],
    this.relevance = 0,
  });

  /// The identifier of the block that carries the passage.
  ///
  /// It is empty when the passage was found in the title of the scene: the
  /// result then points at the scene itself.
  final String blockId;

  /// The identifier of the scene that carries the passage.
  final String sceneId;

  /// The title of the scene.
  final String sceneTitle;

  /// The identifier of the project the scene belongs to.
  final String projectId;

  /// The title of the project.
  final String projectTitle;

  /// The identifier of the CRDT document of the scene.
  final String documentId;

  /// The passage found, with the words that surround it.
  final String excerpt;

  /// The places of the query found in [excerpt].
  final List<SearchHighlight> highlights;

  /// The relevance of the result: the higher, the closer to the query.
  ///
  /// The relevance is computed by the index; it is never negative, and two
  /// results are ordered by it.
  final double relevance;

  /// Whether the passage was found in the text of a block.
  ///
  /// A result that carries no block is a result on the title of a scene: it
  /// opens the scene, not a block of it.
  bool get isBlock => blockId.isNotEmpty;

  /// Returns a copy of this result with the given fields replaced.
  SearchResult copyWith({
    String? blockId,
    String? sceneId,
    String? sceneTitle,
    String? projectId,
    String? projectTitle,
    String? documentId,
    String? excerpt,
    List<SearchHighlight>? highlights,
    double? relevance,
  }) {
    return SearchResult(
      blockId: blockId ?? this.blockId,
      sceneId: sceneId ?? this.sceneId,
      sceneTitle: sceneTitle ?? this.sceneTitle,
      projectId: projectId ?? this.projectId,
      projectTitle: projectTitle ?? this.projectTitle,
      documentId: documentId ?? this.documentId,
      excerpt: excerpt ?? this.excerpt,
      highlights: highlights ?? this.highlights,
      relevance: relevance ?? this.relevance,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchResult &&
          other.blockId == blockId &&
          other.sceneId == sceneId &&
          other.sceneTitle == sceneTitle &&
          other.projectId == projectId &&
          other.projectTitle == projectTitle &&
          other.documentId == documentId &&
          other.excerpt == excerpt &&
          other.relevance == relevance &&
          _sameHighlights(other.highlights, highlights));

  @override
  int get hashCode => Object.hash(
    blockId,
    sceneId,
    sceneTitle,
    projectId,
    projectTitle,
    documentId,
    excerpt,
    relevance,
    Object.hashAll(highlights),
  );

  @override
  String toString() =>
      'SearchResult($sceneTitle, block: $blockId, excerpt: $excerpt)';
}

/// A place of the excerpt where the query was found.
///
/// The bounds are the offsets of the passage inside the excerpt: the first
/// character is at `0`, the last one at the length of the excerpt.
@immutable
final class SearchHighlight {
  /// Creates a highlight.
  const SearchHighlight({required this.start, required this.end});

  /// The offset of the first character of the passage.
  final int start;

  /// The offset of the character that follows the passage.
  final int end;

  /// The length of the passage.
  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHighlight && other.start == start && other.end == end);

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SearchHighlight($start, $end)';
}

/// The number of passages a search returns when the caller does not ask for
/// a number of its own.
const int defaultSearchLimit = 50;

/// The search of the manuscript of the author.
///
/// The search is **local**: it answers from the SQLite database of the
/// device, never from the network. It is the promise of the product — the
/// author finds a passage in his manuscript even without a connection.
///
/// The implementation lives in `lib/src/data/`.
abstract interface class SearchRepository {
  /// The passages that carry the text [query], the most relevant first.
  ///
  /// The query is **escaped**: it is a list of words, never a syntax. A
  /// search of `*` or of `"` therefore finds nothing, and never raises an
  /// error of the database.
  ///
  /// An empty query returns an empty list: the index is never swept for it.
  Future<List<SearchResult>> search(
    String query, {
    int limit = defaultSearchLimit,
  });
}

/// Compares two lists of highlights.
bool _sameHighlights(List<SearchHighlight> left, List<SearchHighlight> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
