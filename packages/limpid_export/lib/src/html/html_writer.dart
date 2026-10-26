import 'dart:convert';
import 'dart:typed_data';

import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import '../util/html_escape.dart';
import 'html_styles.dart';

/// Generateur HTML.
///
/// Deux variantes sont disponibles : l'ebook (HTML semantique avec styles
/// inline) et la page de vente (balises Open Graph et JSON-LD `Book`).
class HtmlWriter {
  /// Cree un generateur HTML.
  const HtmlWriter();

  /// Serialise l'ebook HTML et renvoie les octets du fichier.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final content = renderEbook(book, options);
    return Uint8List.fromList(utf8.encode(content));
  }

  /// Serialise l'ebook HTML et renvoie le texte du document.
  String renderEbook(ExportBook book, ExportOptions options) {
    final buffer = StringBuffer();
    final language = _languageTag(book.language);

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="$language">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="utf-8">');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    );
    buffer.writeln('<title>${HtmlEscape.text(book.title)}</title>');
    if (book.authors.isNotEmpty) {
      buffer.writeln(
        '<meta name="author" content="${HtmlEscape.attribute(book.authors.join(', '))}">',
      );
    }
    final description = book.metadata.description;
    if (description != null && description.isNotEmpty) {
      buffer.writeln(
        '<meta name="description" content="${HtmlEscape.attribute(description)}">',
      );
    }
    buffer.writeln('<meta name="generator" content="Limpid">');
    buffer.writeln('<style>${HtmlStyles.ebook}</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<article class="book">');

    _writeHeader(buffer, book, options);
    _writeChapters(buffer, book);

    buffer.writeln('</article>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  void _writeHeader(
    StringBuffer buffer,
    ExportBook book,
    ExportOptions options,
  ) {
    buffer.writeln('<header class="book-header">');
    if (options.includeCoverImage && book.coverImage != null) {
      final cover = book.coverImage!;
      buffer.writeln(
        '<figure><img src="${HtmlEscape.attribute(cover.fileName ?? _coverPath(book))}"'
        ' alt="${HtmlEscape.attribute(cover.altText ?? book.title)}"></figure>',
      );
    }
    buffer.writeln(
      '<h1 class="book-title">${HtmlEscape.text(book.title)}</h1>',
    );
    final subtitle = book.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      buffer.writeln(
        '<p class="book-subtitle">${HtmlEscape.text(subtitle)}</p>',
      );
    }
    if (book.authors.isNotEmpty) {
      buffer.writeln(
        '<p class="book-authors">${HtmlEscape.text(book.authors.join(', '))}</p>',
      );
    }
    buffer.writeln('</header>');
  }

  void _writeChapters(StringBuffer buffer, ExportBook book) {
    var footnoteIndex = 0;
    for (var index = 0; index < book.chapters.length; index++) {
      final chapter = book.chapters[index];
      final anchor = chapter.identifier ?? 'chapitre-${index + 1}';
      buffer.writeln(
        '<section class="chapter" id="${HtmlEscape.attribute(anchor)}">',
      );
      buffer.writeln(
        '<h2 class="chapter-title">${HtmlEscape.text(chapter.title)}</h2>',
      );

      final notes = <_HtmlFootnote>[];
      for (final block in chapter.blocks) {
        _writeBlock(buffer, block, notes, () {
          footnoteIndex++;
          return footnoteIndex;
        });
      }

      if (notes.isNotEmpty) {
        buffer.writeln('<section class="footnotes">');
        buffer.writeln('<h2>Notes</h2>');
        buffer.writeln('<ol>');
        for (final note in notes) {
          buffer.writeln(
            '<li id="note-${note.number}">${HtmlEscape.text(note.text)}</li>',
          );
        }
        buffer.writeln('</ol>');
        buffer.writeln('</section>');
      }

      buffer.writeln('</section>');
    }
  }

  void _writeBlock(
    StringBuffer buffer,
    ExportBlock block,
    List<_HtmlFootnote> notes,
    int Function() nextFootnote,
  ) {
    switch (block.type) {
      case ExportBlockType.paragraph:
        buffer.write('<p>${HtmlEscape.text(block.text)}');
        _writeFootnoteMarkers(buffer, block, notes, nextFootnote);
        buffer.writeln('</p>');
      case ExportBlockType.heading1:
        buffer.writeln('<h2>${HtmlEscape.text(block.text)}</h2>');
      case ExportBlockType.heading2:
        buffer.writeln('<h3>${HtmlEscape.text(block.text)}</h3>');
      case ExportBlockType.heading3:
        buffer.writeln('<h4>${HtmlEscape.text(block.text)}</h4>');
      case ExportBlockType.listItem:
        buffer.writeln('<ul><li>${HtmlEscape.text(block.text)}</li></ul>');
      case ExportBlockType.quote:
        buffer.writeln(
          '<blockquote><p>${HtmlEscape.text(block.text)}</p></blockquote>',
        );
      case ExportBlockType.code:
        buffer.writeln(
          '<pre><code>${HtmlEscape.text(block.text)}</code></pre>',
        );
      case ExportBlockType.image:
        _writeImage(buffer, block);
      case ExportBlockType.pageBreak:
        buffer.writeln('<div class="page-break"></div>');
      case ExportBlockType.footnote:
        final number = nextFootnote();
        notes.add(_HtmlFootnote(number, block.text));
    }
  }

  void _writeFootnoteMarkers(
    StringBuffer buffer,
    ExportBlock block,
    List<_HtmlFootnote> notes,
    int Function() nextFootnote,
  ) {
    for (final note in block.footnotes) {
      final number = nextFootnote();
      notes.add(_HtmlFootnote(number, note));
      buffer.write(
        ' <a class="footnote-ref" id="ref-$number" href="#note-$number">[$number]</a>',
      );
    }
  }

  void _writeImage(StringBuffer buffer, ExportBlock block) {
    final image = block.image;
    if (image == null) {
      return;
    }
    final source = block.href ?? image.fileName ?? 'image.${image.extension}';
    buffer.writeln(
      '<figure><img src="${HtmlEscape.attribute(source)}"'
      ' alt="${HtmlEscape.attribute(image.altText ?? block.text)}">'
      '</figure>',
    );
  }

  /// Nom de fichier recommande pour l'export HTML.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'html');

  /// Type MIME du fichier produit.
  static const String mimeType = 'text/html; charset=utf-8';

  static String _languageTag(String language) {
    final separator = language.indexOf('-');
    if (separator < 0) {
      return language;
    }
    return language.substring(0, separator).toLowerCase();
  }

  static String _coverPath(ExportBook book) =>
      'images/${FileNames.slug(book.title)}-cover.${book.coverImage?.extension ?? 'jpg'}';
}

class _HtmlFootnote {
  const _HtmlFootnote(this.number, this.text);

  final int number;
  final String text;
}
