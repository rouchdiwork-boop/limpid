import 'dart:typed_data';

import '../model/export_book.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/deterministic_id.dart';
import '../util/file_name.dart';
import '../util/xml_writer.dart';
import '../util/zip_builder.dart';
import 'epub_css.dart';
import 'epub_nav.dart';
import 'epub_opf.dart';
import 'epub_xhtml.dart';

/// Generateur EPUB 3.
///
/// Le paquet produit est un ZIP dont la premiere entree, `mimetype`, est
/// stockee sans compression : c'est une exigence de la specification EPUB 3.
class Epub3Writer {
  /// Cree un generateur EPUB 3.
  const Epub3Writer({
    this.opfWriter = const EpubOpfWriter(),
    this.xhtmlWriter = const EpubXhtmlWriter(),
    this.navWriter = const EpubNavWriter(),
  });

  /// Generateur du paquet OPF.
  final EpubOpfWriter opfWriter;

  /// Generateur des documents XHTML.
  final EpubXhtmlWriter xhtmlWriter;

  /// Generateur de la navigation.
  final EpubNavWriter navWriter;

  /// Type MIME du paquet EPUB.
  static const String mimeType = 'application/epub+zip';

  /// Serialise le livre et renvoie les octets du paquet EPUB.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final imagePaths = <ExportImage, String>{};
    final payloads = <String, ExportImage>{};
    var imageIndex = 0;
    for (final chapter in book.chapters) {
      for (final block in chapter.blocks) {
        final image = block.image;
        if (image == null || imagePaths.containsKey(image)) {
          continue;
        }
        imageIndex++;
        final relativePath = 'images/image-$imageIndex.${image.extension}';
        imagePaths[image] = relativePath;
        payloads['OEBPS/$relativePath'] = image;
      }
    }

    ExportImage? cover;
    String? coverPath;
    if (options.includeCoverImage) {
      cover = book.coverImage;
      if (cover != null) {
        coverPath = 'OEBPS/images/cover.${cover.extension}';
        payloads[coverPath] = cover;
      }
    }

    const cssPath = 'OEBPS/styles/epub.css';
    final chapters = <EpubChapterDocument>[];
    for (var index = 0; index < book.chapters.length; index++) {
      final chapter = book.chapters[index];
      final fileName = 'chapter-${FileNames.chapterNumber(index)}.xhtml';
      chapters.add(
        EpubChapterDocument(
          fileName: fileName,
          title: chapter.title,
          content: xhtmlWriter.renderChapter(
            book,
            chapter,
            cssHref: 'styles/epub.css',
            imagePaths: imagePaths,
          ),
        ),
      );
    }

    final navEntries = <EpubNavEntry>[
      for (final chapter in chapters)
        EpubNavEntry(title: chapter.title, href: chapter.fileName),
    ];

    final items = <EpubOpfItem>[
      const EpubOpfItem(
        id: 'nav',
        href: 'nav.xhtml',
        mediaType: 'application/xhtml+xml',
        properties: 'nav',
      ),
      const EpubOpfItem(
        id: 'ncx',
        href: 'toc.ncx',
        mediaType: 'application/x-dtbncx+xml',
      ),
      const EpubOpfItem(
        id: 'css',
        href: 'styles/epub.css',
        mediaType: 'text/css',
      ),
      for (var index = 0; index < chapters.length; index++)
        EpubOpfItem(
          id: 'chapter-${index + 1}',
          href: chapters[index].fileName,
          mediaType: 'application/xhtml+xml',
        ),
      for (final payload in payloads.entries)
        EpubOpfItem(
          id: 'image-${payload.key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-')}',
          href: payload.key.replaceFirst('OEBPS/', ''),
          mediaType: payload.value.mimeType,
          properties: payload.key == coverPath ? 'cover-image' : null,
        ),
    ];

    final spine = <String>[
      for (var index = 0; index < chapters.length; index++)
        'chapter-${index + 1}',
    ];

    final identifier = 'urn:uuid:${DeterministicIds.uuidFrom(_seed(book))}';
    final modified = _modifiedDate(book, options);

    final zip = ZipBuilder()
      ..addString('mimetype', mimeType, store: true)
      ..addString('META-INF/container.xml', _containerXml())
      ..addString(
        'OEBPS/content.opf',
        opfWriter.render(
          book: book,
          identifier: identifier,
          modified: modified,
          items: items,
          spine: spine,
        ),
      )
      ..addString(
        'OEBPS/nav.xhtml',
        navWriter.renderNav(
          bookTitle: book.title,
          language: book.language,
          cssHref: 'styles/epub.css',
          entries: navEntries,
        ),
      )
      ..addString(
        'OEBPS/toc.ncx',
        navWriter.renderNcx(
          bookTitle: book.title,
          identifier: identifier,
          authors: book.authors,
          entries: navEntries,
        ),
      )
      ..addString(cssPath, EpubCss.content);

    for (final chapter in chapters) {
      zip.addString('OEBPS/${chapter.fileName}', chapter.content);
    }
    for (final payload in payloads.entries) {
      zip.addBytes(payload.key, payload.value.bytes);
    }

    return zip.build();
  }

  /// Nom de fichier recommande pour l'export EPUB.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'epub');

  static String _containerXml() {
    final writer = XmlWriter();
    writer.element(
      'container',
      attributes: <String, String>{
        'version': '1.0',
        'xmlns': 'urn:oasis:names:tc:opendocument:xmlns:container',
      },
      nest: () {
        writer.element(
          'rootfiles',
          nest: () {
            writer.element(
              'rootfile',
              attributes: <String, String>{
                'full-path': 'OEBPS/content.opf',
                'media-type': 'application/oebps-package+xml',
              },
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  static String _seed(ExportBook book) {
    return '${book.title}|${book.language}|${book.authors.join(',')}';
  }

  static DateTime _modifiedDate(ExportBook book, ExportOptions options) {
    return options.exportDate ??
        book.metadata.publicationDate ??
        DateTime.utc(2020);
  }
}
