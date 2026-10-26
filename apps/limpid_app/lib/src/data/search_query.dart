/// The words of a search query.
///
/// ## Why the query is cut into words
///
/// FTS5 gives a meaning to some characters — `*`, `"`, `:`, `^`, `-` — and a
/// query that carries them is a **syntax**, not a text. A writer who types
/// `"` while looking for a quotation must not make the database fail.
///
/// The query is therefore cut into words, and the characters that are
/// neither a letter nor a digit are separators. What reaches FTS5 is always
/// a list of literal words: a search of `*` finds nothing, and never raises
/// an error.
library;

/// The characters that separate two words of a query.
///
/// Everything that is neither a letter nor a digit separates two words.
final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The words of [query], in the order they are written.
///
/// A query that holds no word — a query of `*`, of `"` or of spaces — yields
/// an empty list: there is nothing to look for.
List<String> searchTermsOf(String query) {
  final List<String> terms = <String>[];
  for (final String word in query.split(_separators)) {
    if (word.isEmpty) continue;
    terms.add(word);
  }
  return List<String>.unmodifiable(terms);
}

/// The expression FTS5 searches for the words of [terms].
///
/// Every word is quoted: the expression is a list of literal words, and the
/// characters of the query never reach the syntax of FTS5. The words are
/// joined by a space, which FTS5 reads as a conjunction: a passage carries
/// every word of the query.
String searchMatchOf(List<String> terms) {
  return terms
      .map((String term) => '"${term.replaceAll('"', '""')}"')
      .join(' ');
}
