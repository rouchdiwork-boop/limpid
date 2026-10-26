import 'dart:convert';

import '../model/export_book.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import '../util/html_escape.dart';
import 'html_styles.dart';

/// Generateur de page de vente HTML.
///
/// La page est destinee a la vitrine publique : elle porte les balises Open
/// Graph (partage sur les reseaux sociaux) et un bloc JSON-LD de type
/// `Book` (referencement par les moteurs de recherche).
class HtmlSalesPageWriter {
  /// Cree un generateur de page de vente.
  const HtmlSalesPageWriter();

  /// Serialise la page de vente.
  String render(ExportBook book, ExportOptions options) {
    final buffer = StringBuffer();
    final language = _languageTag(book.language);
    final metadata = book.metadata;
    final coverUrl = _coverUrl(book);
    final description = metadata.description ?? book.subtitle ?? book.title;

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="$language">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="utf-8">');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    );
    buffer.writeln('<title>${HtmlEscape.text(book.title)}</title>');
    buffer.writeln(
      '<meta name="description" content="${HtmlEscape.attribute(description)}">',
    );
    buffer.writeln('<meta name="generator" content="Limpid">');

    // Open Graph.
    buffer.writeln('<meta property="og:type" content="book">');
    buffer.writeln(
      '<meta property="og:title" content="${HtmlEscape.attribute(book.title)}">',
    );
    if (book.subtitle != null) {
      buffer.writeln(
        '<meta property="og:description" content="${HtmlEscape.attribute(book.subtitle!)}">',
      );
    } else {
      buffer.writeln(
        '<meta property="og:description" content="${HtmlEscape.attribute(description)}">',
      );
    }
    if (coverUrl != null) {
      buffer.writeln(
        '<meta property="og:image" content="${HtmlEscape.attribute(coverUrl)}">',
      );
    }
    buffer.writeln(
      '<meta property="og:locale" content="${HtmlEscape.attribute(language)}">',
    );
    buffer.writeln('<meta property="og:site_name" content="Limpid">');

    // Twitter / X.
    buffer.writeln('<meta name="twitter:card" content="summary_large_image">');
    buffer.writeln(
      '<meta name="twitter:title" content="${HtmlEscape.attribute(book.title)}">',
    );
    buffer.writeln(
      '<meta name="twitter:description" content="${HtmlEscape.attribute(description)}">',
    );
    if (coverUrl != null) {
      buffer.writeln(
        '<meta name="twitter:image" content="${HtmlEscape.attribute(coverUrl)}">',
      );
    }

    buffer.writeln('<style>${HtmlStyles.salesPage}</style>');
    buffer.writeln('<script type="application/ld+json">');
    buffer.writeln(_jsonLd(book, coverUrl));
    buffer.writeln('</script>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<main class="page">');
    buffer.writeln('<header class="hero">');
    if (coverUrl != null) {
      buffer.writeln(
        '<img class="cover" src="${HtmlEscape.attribute(coverUrl)}"'
        ' alt="${HtmlEscape.attribute(book.coverImage?.altText ?? book.title)}">',
      );
    }
    buffer.writeln('<h1 class="title">${HtmlEscape.text(book.title)}</h1>');
    if (book.subtitle != null) {
      buffer.writeln(
        '<p class="subtitle">${HtmlEscape.text(book.subtitle!)}</p>',
      );
    }
    if (book.authors.isNotEmpty) {
      buffer.writeln(
        '<p class="authors">${HtmlEscape.text(book.authors.join(', '))}</p>',
      );
    }
    buffer.writeln('</header>');

    if (metadata.description != null) {
      buffer.writeln(
        '<section class="description"><p>${HtmlEscape.text(metadata.description!)}</p></section>',
      );
    }

    buffer.writeln('<section class="meta">');
    buffer.writeln('<dl>');
    if (metadata.isbn != null) {
      buffer.writeln(
        '<dt>ISBN</dt><dd>${HtmlEscape.text(metadata.isbn!)}</dd>',
      );
    }
    if (metadata.publisher != null) {
      buffer.writeln(
        '<dt>Editeur</dt><dd>${HtmlEscape.text(metadata.publisher!)}</dd>',
      );
    }
    final date = metadata.publicationDate;
    if (date != null) {
      buffer.writeln(
        '<dt>Publication</dt><dd>${HtmlEscape.text(_formatDate(date))}</dd>',
      );
    }
    buffer.writeln('<dt>Format</dt><dd>EPUB, PDF et DOCX</dd>');
    buffer.writeln('</dl>');
    buffer.writeln('</section>');

    buffer.writeln('</main>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  /// Bloc JSON-LD de type `Book`.
  String jsonLd(ExportBook book) => _jsonLd(book, _coverUrl(book));

  String _jsonLd(ExportBook book, String? coverUrl) {
    final metadata = book.metadata;
    final document = <String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'Book',
      'name': book.title,
      if (book.subtitle != null) 'alternateName': book.subtitle,
      if (book.authors.isNotEmpty)
        'author': <Map<String, String>>[
          for (final author in book.authors)
            <String, String>{'@type': 'Person', 'name': author},
        ],
      if (metadata.publisher != null)
        'publisher': <String, String>{
          '@type': 'Organization',
          'name': metadata.publisher!,
        },
      if (metadata.description != null) 'description': metadata.description,
      if (metadata.isbn != null) 'isbn': metadata.isbn,
      if (metadata.publicationDate != null)
        'datePublished': _formatDate(metadata.publicationDate!),
      'inLanguage': book.language,
      'bookFormat': 'https://schema.org/EBook',
      'image': ?coverUrl,
      if (metadata.subjects.isNotEmpty) 'keywords': metadata.subjects,
      if (metadata.rights != null) 'copyrightNotice': metadata.rights,
    };

    final encoded = jsonEncode(document);
    // Neutralise la fermeture prematuree du bloc script.
    return encoded.replaceAll('<', _unicodeEscape);
  }

  /// Sequence d'echappement Unicode pour le caractere `<`.
  static const String _unicodeEscape = '\\u003c';

  /// Nom de fichier recommande pour la page de vente.
  static String fileNameFor(ExportBook book) =>
      '${FileNames.slug(book.title)}-page-de-vente.html';

  static String? _coverUrl(ExportBook book) {
    final cover = book.coverImage;
    if (cover == null) {
      return null;
    }
    return cover.fileName ??
        'images/${FileNames.slug(book.title)}-cover.${cover.extension}';
  }

  static String _languageTag(String language) {
    final separator = language.indexOf('-');
    if (separator < 0) {
      return language;
    }
    return language.substring(0, separator).toLowerCase();
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
