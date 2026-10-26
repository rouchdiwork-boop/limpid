import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_chapter.dart';
import '../model/export_image.dart';
import '../util/xml_writer.dart';

/// Resultat du rendu d'un chapitre EPUB.
class EpubChapterDocument {
  /// Cree un document de chapitre.
  const EpubChapterDocument({
    required this.fileName,
    required this.title,
    required this.content,
  });

  /// Nom du fichier XHTML dans le paquet EPUB.
  final String fileName;

  /// Titre du chapitre (utilise dans la table des matieres).
  final String title;

  /// Contenu XHTML complet du chapitre.
  final String content;
}

/// Generateur des documents XHTML d'un EPUB.
class EpubXhtmlWriter {
  const EpubXhtmlWriter();

  /// Namespace XHTML.
  static const String xhtmlNamespace = 'http://www.w3.org/1999/xhtml';

  /// Namespace `epub` (operations de publication).
  static const String epubNamespace = 'http://www.idpf.org/2007/ops';

  /// Serialise un chapitre.
  String renderChapter(
    ExportBook book,
    ExportChapter chapter, {
    required String cssHref,
    required Map<ExportImage, String> imagePaths,
  }) {
    final writer = XmlWriter(doctype: 'html');
    writer.element(
      'html',
      attributes: <String, String>{
        'xmlns': xhtmlNamespace,
        'xmlns:epub': epubNamespace,
        'xml:lang': book.language,
        'lang': book.language,
      },
      nest: () {
        writer.element(
          'head',
          nest: () {
            writer.element(
              'meta',
              attributes: <String, String>{'charset': 'utf-8'},
            );
            writer.element('title', nest: () => writer.text(chapter.title));
            writer.element(
              'link',
              attributes: <String, String>{
                'rel': 'stylesheet',
                'type': 'text/css',
                'href': cssHref,
              },
            );
          },
        );
        writer.element(
          'body',
          nest: () {
            writer.element(
              'section',
              attributes: <String, String>{'epub:type': 'chapter'},
              nest: () {
                writer.element('h1', nest: () => writer.text(chapter.title));
                _writeBlocks(writer, chapter, imagePaths);
              },
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  void _writeBlocks(
    XmlWriter writer,
    ExportChapter chapter,
    Map<ExportImage, String> imagePaths,
  ) {
    final notes = <_EpubNote>[];
    for (final block in chapter.blocks) {
      _writeBlock(writer, block, imagePaths, notes);
    }
    if (notes.isEmpty) {
      return;
    }
    writer.element(
      'aside',
      attributes: <String, String>{'epub:type': 'footnotes'},
      nest: () {
        for (final note in notes) {
          writer.element(
            'aside',
            attributes: <String, String>{
              'epub:type': 'footnote',
              'id': 'note-${note.number}',
            },
            nest: () {
              writer.element(
                'p',
                nest: () {
                  writer.element(
                    'a',
                    attributes: <String, String>{
                      'epub:type': 'noteref',
                      'href': '#note-${note.number}',
                    },
                    nest: () => writer.text('${note.number}'),
                  );
                  writer.text(' ${note.text}');
                },
              );
            },
          );
        }
      },
    );
  }

  void _writeBlock(
    XmlWriter writer,
    ExportBlock block,
    Map<ExportImage, String> imagePaths,
    List<_EpubNote> notes,
  ) {
    switch (block.type) {
      case ExportBlockType.paragraph:
        writer.element(
          'p',
          nest: () {
            writer.text(block.text);
            for (final note in block.footnotes) {
              notes.add(_EpubNote(notes.length + 1, note));
              writer.element(
                'a',
                attributes: <String, String>{
                  'epub:type': 'noteref',
                  'href': '#note-${notes.length}',
                  'id': 'noteref-${notes.length}',
                },
                nest: () => writer.text('${notes.length}'),
              );
            }
          },
        );
      case ExportBlockType.heading1:
        writer.element('h2', nest: () => writer.text(block.text));
      case ExportBlockType.heading2:
        writer.element('h3', nest: () => writer.text(block.text));
      case ExportBlockType.heading3:
        writer.element('h4', nest: () => writer.text(block.text));
      case ExportBlockType.listItem:
        writer.element(
          'ul',
          nest: () {
            writer.element('li', nest: () => writer.text(block.text));
          },
        );
      case ExportBlockType.quote:
        writer.element(
          'blockquote',
          nest: () {
            writer.element('p', nest: () => writer.text(block.text));
          },
        );
      case ExportBlockType.code:
        writer.element(
          'pre',
          nest: () {
            writer.element('code', nest: () => writer.text(block.text));
          },
        );
      case ExportBlockType.image:
        _writeImage(writer, block, imagePaths);
      case ExportBlockType.pageBreak:
        writer.element(
          'p',
          attributes: <String, String>{'style': 'page-break-after: always'},
          nest: () => writer.text(''),
        );
      case ExportBlockType.footnote:
        notes.add(_EpubNote(notes.length + 1, block.text));
    }
  }

  void _writeImage(
    XmlWriter writer,
    ExportBlock block,
    Map<ExportImage, String> imagePaths,
  ) {
    final image = block.image;
    if (image == null) {
      return;
    }
    final path =
        imagePaths[image] ??
        'images/${image.fileName ?? 'image.${image.extension}'}';
    writer.element(
      'figure',
      nest: () {
        writer.element(
          'img',
          attributes: <String, String>{
            'src': path,
            'alt': image.altText ?? block.text,
          },
        );
      },
    );
  }
}

class _EpubNote {
  const _EpubNote(this.number, this.text);

  final int number;
  final String text;
}
