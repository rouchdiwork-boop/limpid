import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_chapter.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/xml_writer.dart';
import 'docx_image_xml.dart';
import 'docx_numbering_xml.dart';
import 'docx_package.dart';

/// Illustration preparee pour l'inclusion dans le document Word.
class DocxImage {
  /// Cree une description d'illustration.
  const DocxImage({
    required this.relationshipId,
    required this.widthEmu,
    required this.heightEmu,
  });

  /// Identifiant de la relation dans `document.xml.rels`.
  final String relationshipId;

  /// Largeur affichee, en EMU (1 pt = 12700 EMU).
  final int widthEmu;

  /// Hauteur affichee, en EMU.
  final int heightEmu;
}

/// Generateur de `word/document.xml`.
class DocxDocumentXml {
  /// Cree un generateur de corps de document.
  const DocxDocumentXml({this.imageXml = const DocxImageXml()});

  /// Generateur des dessins d'illustration.
  final DocxImageXml imageXml;

  /// Nombre de twips par millimetre.
  static const double _twipsPerMm = 1440 / 25.4;

  /// Nombre d'EMU par point.
  static const int _emuPerPoint = 12700;

  /// Serialise le corps du document.
  ///
  /// [footnotes] est remplit par le rendu : l'identifiant d'une note est son
  /// index dans cette liste, plus un.
  String render({
    required ExportBook book,
    required ExportOptions options,
    required List<String> footnotes,
    required Map<ExportImage, DocxImage> images,
  }) {
    var footnoteCounter = 0;
    int nextFootnote() {
      footnoteCounter++;
      return footnoteCounter;
    }

    final writer = XmlWriter();
    writer.element(
      'w:document',
      attributes: <String, String>{
        'xmlns:w': DocxPackage.wordNamespace,
        'xmlns:r': DocxPackage.officeRelationships,
        'xmlns:wp':
            'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
        'xmlns:a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
        'xmlns:pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
      },
      nest: () {
        writer.element(
          'w:body',
          nest: () {
            _writeTitleBlock(writer, book);
            for (var index = 0; index < book.chapters.length; index++) {
              final chapter = book.chapters[index];
              _writeChapter(writer, chapter, footnotes, images, nextFootnote);
              final isLast = index == book.chapters.length - 1;
              if (!isLast) {
                _writeSectionBreak(writer, options);
              }
            }
            _writeSectionProperties(writer, options);
          },
        );
      },
    );
    return writer.toXmlString();
  }

  void _writeTitleBlock(XmlWriter writer, ExportBook book) {
    _writeStyledParagraph(writer, 'Title', book.title);
    final subtitle = book.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      _writeStyledParagraph(writer, 'Subtitle', subtitle);
    }
    for (final author in book.authors) {
      _writeStyledParagraph(writer, 'Subtitle', author);
    }
  }

  void _writeChapter(
    XmlWriter writer,
    ExportChapter chapter,
    List<String> footnotes,
    Map<ExportImage, DocxImage> images,
    int Function() nextFootnote,
  ) {
    _writeStyledParagraph(writer, 'Heading1', chapter.title);
    for (final block in chapter.blocks) {
      switch (block.type) {
        case ExportBlockType.paragraph:
          _writeParagraph(writer, block, footnotes, nextFootnote);
        case ExportBlockType.heading1:
          _writeStyledParagraph(writer, 'Heading1', block.text);
        case ExportBlockType.heading2:
          _writeStyledParagraph(writer, 'Heading2', block.text);
        case ExportBlockType.heading3:
          _writeStyledParagraph(writer, 'Heading3', block.text);
        case ExportBlockType.listItem:
          _writeListItem(writer, block);
        case ExportBlockType.quote:
          _writeStyledParagraph(writer, 'Quote', block.text);
        case ExportBlockType.code:
          _writeStyledParagraph(writer, 'Code', block.text);
        case ExportBlockType.image:
          _writeImage(writer, block, images);
        case ExportBlockType.pageBreak:
          _writePageBreak(writer);
        case ExportBlockType.footnote:
          final id = nextFootnote();
          footnotes.add(block.text);
          writer.element(
            'w:p',
            nest: () {
              writer.element(
                'w:pPr',
                nest: () {
                  writer.element(
                    'w:pStyle',
                    attributes: <String, String>{'w:val': 'BodyText'},
                  );
                },
              );
              _writeFootnoteReference(writer, id);
            },
          );
      }
    }
  }

  void _writeParagraph(
    XmlWriter writer,
    ExportBlock block,
    List<String> footnotes,
    int Function() nextFootnote,
  ) {
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:pPr',
          nest: () {
            writer.element(
              'w:pStyle',
              attributes: <String, String>{'w:val': 'BodyText'},
            );
          },
        );
        _writeRun(writer, block.text);
        for (final note in block.footnotes) {
          final id = nextFootnote();
          footnotes.add(note);
          _writeFootnoteReference(writer, id);
        }
      },
    );
  }

  void _writeFootnoteReference(XmlWriter writer, int id) {
    writer.element(
      'w:r',
      nest: () {
        writer.element(
          'w:rPr',
          nest: () {
            writer.element(
              'w:rStyle',
              attributes: <String, String>{'w:val': 'FootnoteReference'},
            );
          },
        );
        writer.element(
          'w:footnoteReference',
          attributes: <String, String>{'w:id': '$id'},
        );
      },
    );
  }

  void _writeListItem(XmlWriter writer, ExportBlock block) {
    final level = ((block.level ?? 1) - 1).clamp(0, 2);
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:pPr',
          nest: () {
            writer.element(
              'w:pStyle',
              attributes: <String, String>{'w:val': 'ListParagraph'},
            );
            writer.element(
              'w:numPr',
              nest: () {
                writer.element(
                  'w:ilvl',
                  attributes: <String, String>{'w:val': '$level'},
                );
                writer.element(
                  'w:numId',
                  attributes: <String, String>{
                    'w:val': '${DocxNumberingXml.bulletNumberId}',
                  },
                );
              },
            );
          },
        );
        _writeRun(writer, block.text);
      },
    );
  }

  void _writeImage(
    XmlWriter writer,
    ExportBlock block,
    Map<ExportImage, DocxImage> images,
  ) {
    final image = block.image;
    if (image == null) {
      return;
    }
    final described = images[image];
    if (described == null) {
      return;
    }
    imageXml.write(
      writer,
      image: image,
      described: described,
      description: image.altText ?? block.text,
    );
  }

  void _writePageBreak(XmlWriter writer) {
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:r',
          nest: () {
            writer.element(
              'w:br',
              attributes: <String, String>{'w:type': 'page'},
            );
          },
        );
      },
    );
  }

  void _writeStyledParagraph(XmlWriter writer, String style, String text) {
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:pPr',
          nest: () {
            writer.element(
              'w:pStyle',
              attributes: <String, String>{'w:val': style},
            );
          },
        );
        _writeRun(writer, text);
      },
    );
  }

  void _writeRun(XmlWriter writer, String text) {
    writer.element(
      'w:r',
      nest: () {
        writer.element(
          'w:t',
          attributes: <String, String>{'xml:space': 'preserve'},
          nest: () => writer.text(text),
        );
      },
    );
  }

  void _writeSectionBreak(XmlWriter writer, ExportOptions options) {
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:pPr',
          nest: () => _writeSectionProperties(writer, options),
        );
      },
    );
  }

  void _writeSectionProperties(XmlWriter writer, ExportOptions options) {
    writer.element(
      'w:sectPr',
      nest: () {
        writer.element(
          'w:pgSz',
          attributes: <String, String>{
            'w:w': '${_twips(options.pageWidthMm)}',
            'w:h': '${_twips(options.pageHeightMm)}',
          },
        );
        writer.element(
          'w:pgMar',
          attributes: <String, String>{
            'w:top': '${_twips(options.marginTopMm)}',
            'w:right': '${_twips(options.marginOutsideMm)}',
            'w:bottom': '${_twips(options.marginBottomMm)}',
            'w:left': '${_twips(options.marginInsideMm)}',
            'w:header': '${_twips(12)}',
            'w:footer': '${_twips(12)}',
            'w:gutter': '0',
          },
        );
        writer.element(
          'w:cols',
          attributes: <String, String>{'w:space': '708'},
        );
        writer.element(
          'w:docGrid',
          attributes: <String, String>{'w:linePitch': '360'},
        );
      },
    );
  }

  /// Largeur utile de la page, en points.
  static double contentWidthPt(ExportOptions options) {
    final widthMm =
        options.pageWidthMm - options.marginInsideMm - options.marginOutsideMm;
    return widthMm * 72 / 25.4;
  }

  /// Calcule la taille d'affichage d'une image, en EMU.
  static DocxImage describeImage({
    required String relationshipId,
    required int pixelWidth,
    required int pixelHeight,
    required double maxWidthPt,
    required int dpi,
  }) {
    final naturalWidthPt = pixelWidth / dpi * 72;
    final widthPt = naturalWidthPt < maxWidthPt ? naturalWidthPt : maxWidthPt;
    final ratio = pixelHeight == 0 ? 1.0 : pixelWidth / pixelHeight;
    final heightPt = widthPt / ratio;
    return DocxImage(
      relationshipId: relationshipId,
      widthEmu: (widthPt * _emuPerPoint).round(),
      heightEmu: (heightPt * _emuPerPoint).round(),
    );
  }

  static int _twips(double millimetres) => (millimetres * _twipsPerMm).round();
}
