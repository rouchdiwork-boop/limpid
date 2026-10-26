import '../model/export_book.dart';

/// Emetteur de bloc YAML (front matter) pour les exports Markdown.
///
/// Seul l'ecriture est necessaire : le moteur n'analyse jamais de YAML.
class MarkdownFrontMatter {
  const MarkdownFrontMatter._();

  /// Serialise les metadonnees d'un livre au format YAML.
  ///
  /// Le resultat est encadre par `---` ; il est vide si le livre n'a aucune
  /// metadonnee exploitable.
  static String render(ExportBook book) {
    final lines = <String>[];
    final metadata = book.metadata;

    _addScalar(lines, 'title', book.title);
    _addScalar(lines, 'subtitle', book.subtitle);
    if (book.authors.isNotEmpty) {
      _addScalar(lines, 'author', book.authors.join(', '));
    }
    _addScalar(lines, 'isbn', metadata.isbn);
    _addScalar(lines, 'description', metadata.description);
    _addScalar(lines, 'publisher', metadata.publisher);
    _addScalar(lines, 'rights', metadata.rights);
    _addScalar(lines, 'language', book.language);
    final date = metadata.publicationDate;
    if (date != null) {
      lines.add('date: ${_formatDate(date)}');
    }
    _addList(lines, 'subjects', metadata.subjects);
    _addList(lines, 'bisac', metadata.bisac);

    if (lines.isEmpty) {
      return '';
    }
    return '---\n${lines.join('\n')}\n---\n\n';
  }

  static void _addScalar(List<String> lines, String key, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    lines.add('$key: ${_quote(trimmed)}');
  }

  static void _addList(List<String> lines, String key, List<String> values) {
    if (values.isEmpty) {
      return;
    }
    lines.add('$key:');
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      lines.add('  - ${_quote(trimmed)}');
    }
  }

  static String _quote(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', ' ');
    return '"$escaped"';
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
