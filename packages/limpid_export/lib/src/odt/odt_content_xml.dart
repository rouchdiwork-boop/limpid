import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_chapter.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/image_size.dart';
import '../util/xml_writer.dart';
import 'odt_namespaces.dart';

/// Generateur du document `content.xml` d'un paquet ODT.
class OdtContentXml {
  const OdtContentXml();

  /// Serialise le corps du document.
  ///
  /// [imagePaths] associe chaque image a son chemin interne dans le paquet ;
  /// [coverPath] designe l'image de couverture, ajoutee en tete de document.
  String render(
    ExportBook book,
    ExportOptions options, {
    Map<ExportImage, String> imagePaths = const <ExportImage, String>{},
    String? coverPath,
  }) {
    final writer = XmlWriter();
    writer.namespacedElement(
      'office:document-content',
      namespaces: OdtNamespaces.all,
      attributes: <String, String>{'office:version': '1.3'},
      nest: () {
        _writeAutomaticStyles(writer);
        writer.namespacedElement(
          'office:body',
          nest: () {
            writer.namespacedElement(
              'office:text',
              nest: () {
                if (coverPath != null) {
                  _writeCover(writer, coverPath);
                }
                for (final chapter in book.chapters) {
                  _writeChapter(writer, chapter, imagePaths);
                }
              },
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  void _writeCover(XmlWriter writer, String coverPath) {
    writer.namespacedElement(
      'text:p',
      attributes: <String, String>{'text:style-name': 'Standard'},
      nest: () {
        writer.namespacedElement(
          'draw:frame',
          attributes: <String, String>{
            'draw:style-name': 'Image',
            'text:anchor-type': 'as-char',
            'svg:width': '10.00cm',
            'svg:height': '15.00cm',
            'draw:z-index': '0',
          },
          nest: () {
            writer.namespacedElement(
              'draw:image',
              attributes: <String, String>{
                'xlink:href': coverPath,
                'xlink:type': 'simple',
                'xlink:show': 'embed',
                'xlink:actuate': 'onLoad',
              },
            );
          },
        );
      },
    );
  }

  void _writeAutomaticStyles(XmlWriter writer) {
    writer.namespacedElement(
      'office:automatic-styles',
      nest: () {
        _writeParagraphStyle(
          writer,
          name: 'Chapitre',
          parent: 'Standard',
          size: '18pt',
          bold: true,
          marginTop: '0.8cm',
          marginBottom: '0.4cm',
          keepWithNext: true,
        );
        _writeParagraphStyle(
          writer,
          name: 'Section',
          parent: 'Standard',
          size: '14pt',
          bold: true,
          marginTop: '0.6cm',
          marginBottom: '0.2cm',
          keepWithNext: true,
        );
        _writeParagraphStyle(
          writer,
          name: 'SousSection',
          parent: 'Standard',
          size: '12pt',
          bold: true,
          marginTop: '0.5cm',
          marginBottom: '0.2cm',
          keepWithNext: true,
        );
        _writeParagraphStyle(
          writer,
          name: 'Citation',
          parent: 'Standard',
          marginTop: '0.4cm',
          marginBottom: '0.4cm',
          indentLeft: '0.8cm',
          italic: true,
        );
        _writeParagraphStyle(
          writer,
          name: 'Code',
          parent: 'Standard',
          fontFamily: 'IBM Plex Mono',
          size: '10pt',
          marginTop: '0.4cm',
          marginBottom: '0.4cm',
        );
        writer.namespacedElement(
          'style:style',
          attributes: <String, String>{
            'style:name': 'Image',
            'style:family': 'graphic',
          },
          nest: () {
            writer.namespacedElement(
              'style:graphic-properties',
              attributes: <String, String>{
                'draw:stroke': 'none',
                'draw:fill': 'none',
                'fo:padding': '0cm',
              },
            );
          },
        );
      },
    );
  }

  void _writeParagraphStyle(
    XmlWriter writer, {
    required String name,
    required String parent,
    String? size,
    String? fontFamily,
    bool bold = false,
    bool italic = false,
    String? marginTop,
    String? marginBottom,
    String? indentLeft,
    bool keepWithNext = false,
  }) {
    writer.namespacedElement(
      'style:style',
      attributes: <String, String>{
        'style:name': name,
        'style:family': 'paragraph',
        'style:parent-style-name': parent,
      },
      nest: () {
        writer.namespacedElement(
          'style:paragraph-properties',
          attributes: <String, String>{
            'fo:margin-top': ?marginTop,
            'fo:margin-bottom': ?marginBottom,
            'fo:margin-left': ?indentLeft,
            if (keepWithNext) 'fo:keep-with-next': 'always',
          },
        );
        writer.namespacedElement(
          'style:text-properties',
          attributes: <String, String>{
            'fo:font-size': ?size,
            'fo:font-family': ?fontFamily,
            if (bold) 'fo:font-weight': 'bold',
            if (italic) 'fo:font-style': 'italic',
          },
        );
      },
    );
  }

  void _writeChapter(
    XmlWriter writer,
    ExportChapter chapter,
    Map<ExportImage, String> imagePaths,
  ) {
    writer.namespacedElement(
      'text:section',
      attributes: <String, String>{'text:name': chapter.title},
      nest: () {
        writer.namespacedElement(
          'text:h',
          attributes: <String, String>{
            'text:style-name': 'Chapitre',
            'text:outline-level': '1',
          },
          nest: () => writer.text(chapter.title),
        );
        for (final block in chapter.blocks) {
          _writeBlock(writer, block, imagePaths);
        }
      },
    );
  }

  void _writeBlock(
    XmlWriter writer,
    ExportBlock block,
    Map<ExportImage, String> imagePaths,
  ) {
    switch (block.type) {
      case ExportBlockType.paragraph:
        _writeParagraph(writer, block);
      case ExportBlockType.heading1:
        _writeHeading(writer, block.text, 'Section', 2);
      case ExportBlockType.heading2:
        _writeHeading(writer, block.text, 'SousSection', 3);
      case ExportBlockType.heading3:
        _writeHeading(writer, block.text, 'SousSection', 4);
      case ExportBlockType.listItem:
        _writeList(writer, block);
      case ExportBlockType.quote:
        _writeQuote(writer, block);
      case ExportBlockType.code:
        _writeCode(writer, block);
      case ExportBlockType.image:
        _writeImage(writer, block, imagePaths);
      case ExportBlockType.pageBreak:
        writer.namespacedElement(
          'text:p',
          attributes: <String, String>{'text:style-name': 'Standard'},
          nest: () {
            writer.namespacedElement(
              'text:line-break',
              attributes: <String, String>{'text:style-name': 'Standard'},
            );
          },
        );
      case ExportBlockType.footnote:
        writer.namespacedElement(
          'text:p',
          nest: () {
            writer.namespacedElement(
              'text:note',
              attributes: <String, String>{'text:note-class': 'footnote'},
              nest: () {
                writer.namespacedElement('text:note-citation');
                writer.namespacedElement(
                  'text:note-body',
                  nest: () {
                    writer.namespacedElement(
                      'text:p',
                      nest: () => writer.text(block.text),
                    );
                  },
                );
              },
            );
          },
        );
    }
  }

  void _writeParagraph(XmlWriter writer, ExportBlock block) {
    writer.namespacedElement(
      'text:p',
      nest: () {
        writer.text(block.text);
        for (final note in block.footnotes) {
          writer.namespacedElement(
            'text:note',
            attributes: <String, String>{'text:note-class': 'footnote'},
            nest: () {
              writer.namespacedElement('text:note-citation');
              writer.namespacedElement(
                'text:note-body',
                nest: () {
                  writer.namespacedElement(
                    'text:p',
                    nest: () => writer.text(note),
                  );
                },
              );
            },
          );
        }
      },
    );
  }

  void _writeHeading(XmlWriter writer, String text, String style, int level) {
    writer.namespacedElement(
      'text:h',
      attributes: <String, String>{
        'text:style-name': style,
        'text:outline-level': '$level',
      },
      nest: () => writer.text(text),
    );
  }

  void _writeList(XmlWriter writer, ExportBlock block) {
    writer.namespacedElement(
      'text:list',
      nest: () {
        writer.namespacedElement(
          'text:list-item',
          nest: () {
            writer.namespacedElement(
              'text:p',
              nest: () => writer.text(block.text),
            );
          },
        );
      },
    );
  }

  void _writeQuote(XmlWriter writer, ExportBlock block) {
    writer.namespacedElement(
      'text:p',
      attributes: <String, String>{'text:style-name': 'Citation'},
      nest: () => writer.text(block.text),
    );
  }

  void _writeCode(XmlWriter writer, ExportBlock block) {
    writer.namespacedElement(
      'text:p',
      attributes: <String, String>{'text:style-name': 'Code'},
      nest: () => writer.text(block.text),
    );
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
        'Pictures/${image.fileName ?? 'image.${image.extension}'}';
    final dimensions = _dimensions(image);
    writer.namespacedElement(
      'text:p',
      nest: () {
        writer.namespacedElement(
          'draw:frame',
          attributes: <String, String>{
            'draw:style-name': 'Image',
            'text:anchor-type': 'as-char',
            'svg:width': dimensions.$1,
            'svg:height': dimensions.$2,
            'draw:z-index': '0',
          },
          nest: () {
            writer.namespacedElement(
              'draw:image',
              attributes: <String, String>{
                'xlink:href': path,
                'xlink:type': 'simple',
                'xlink:show': 'embed',
                'xlink:actuate': 'onLoad',
              },
            );
          },
        );
      },
    );
  }

  (String, String) _dimensions(ExportImage image) {
    final size = ImageSizes.of(image.bytes);
    if (size == null) {
      return ('10cm', '6cm');
    }
    final maxWidth = 14.0;
    final ratio = size.aspectRatio == 0 ? 1.5 : size.aspectRatio;
    final width = maxWidth;
    final height = width / ratio;
    return ('${width.toStringAsFixed(2)}cm', '${height.toStringAsFixed(2)}cm');
  }
}
