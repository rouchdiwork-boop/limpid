import '../model/export_options.dart';
import '../util/xml_writer.dart';
import 'docx_package.dart';

/// Generateur de `word/styles.xml`.
class DocxStylesXml {
  const DocxStylesXml();

  /// Serialise les styles du document.
  String render(ExportOptions options) {
    final writer = XmlWriter();
    writer.element(
      'w:styles',
      attributes: <String, String>{'xmlns:w': DocxPackage.wordNamespace},
      nest: () {
        writer.element(
          'w:docDefaults',
          nest: () {
            writer.element(
              'w:rPrDefault',
              nest: () {
                writer.element(
                  'w:rPr',
                  nest: () {
                    writer.element(
                      'w:rFonts',
                      attributes: <String, String>{
                        'w:ascii': options.fontFamily,
                        'w:hAnsi': options.fontFamily,
                        'w:cs': options.fontFamily,
                      },
                    );
                    writer.element(
                      'w:sz',
                      attributes: <String, String>{
                        'w:val': '${(options.fontSize * 2).round()}',
                      },
                    );
                    writer.element(
                      'w:szCs',
                      attributes: <String, String>{
                        'w:val': '${(options.fontSize * 2).round()}',
                      },
                    );
                    writer.element(
                      'w:lang',
                      attributes: <String, String>{'w:val': 'fr-FR'},
                    );
                  },
                );
              },
            );
            writer.element(
              'w:pPrDefault',
              nest: () {
                writer.element(
                  'w:pPr',
                  nest: () {
                    writer.element(
                      'w:spacing',
                      attributes: <String, String>{
                        'w:line': '${(options.lineHeight * 240).round()}',
                        'w:lineRule': 'auto',
                        'w:after': '120',
                      },
                    );
                  },
                );
              },
            );
          },
        );
        _writeParagraphStyle(
          writer,
          id: 'Normal',
          name: 'Normal',
          isDefault: true,
        );
        _writeParagraphStyle(
          writer,
          id: 'Title',
          name: 'Title',
          size: 56,
          bold: true,
        );
        _writeParagraphStyle(
          writer,
          id: 'Subtitle',
          name: 'Subtitle',
          size: 28,
          italic: true,
        );
        _writeParagraphStyle(
          writer,
          id: 'Heading1',
          name: 'heading 1',
          size: 36,
          bold: true,
          before: 360,
          after: 160,
          outlineLevel: 0,
        );
        _writeParagraphStyle(
          writer,
          id: 'Heading2',
          name: 'heading 2',
          size: 28,
          bold: true,
          before: 280,
          after: 120,
          outlineLevel: 1,
        );
        _writeParagraphStyle(
          writer,
          id: 'Heading3',
          name: 'heading 3',
          size: 24,
          bold: true,
          before: 240,
          after: 100,
          outlineLevel: 2,
        );
        _writeParagraphStyle(writer, id: 'BodyText', name: 'Body Text');
        _writeParagraphStyle(
          writer,
          id: 'ListParagraph',
          name: 'List Paragraph',
          indentLeft: 720,
        );
        _writeParagraphStyle(
          writer,
          id: 'Quote',
          name: 'Quote',
          italic: true,
          indentLeft: 720,
        );
        _writeParagraphStyle(
          writer,
          id: 'Code',
          name: 'Code',
          font: 'IBM Plex Mono',
          size: 20,
        );
        _writeParagraphStyle(
          writer,
          id: 'FootnoteText',
          name: 'footnote text',
          size: 18,
        );
        _writeCharacterStyle(
          writer,
          id: 'FootnoteReference',
          name: 'footnote reference',
        );
      },
    );
    return writer.toXmlString();
  }

  void _writeParagraphStyle(
    XmlWriter writer, {
    required String id,
    required String name,
    bool isDefault = false,
    int? size,
    bool bold = false,
    bool italic = false,
    String? font,
    int? before,
    int? after,
    int? indentLeft,
    int? outlineLevel,
  }) {
    writer.element(
      'w:style',
      attributes: <String, String>{
        'w:type': 'paragraph',
        'w:styleId': id,
        if (isDefault) 'w:default': '1',
      },
      nest: () {
        writer.element('w:name', attributes: <String, String>{'w:val': name});
        writer.element('w:qFormat');
        writer.element(
          'w:pPr',
          nest: () {
            if (before != null || after != null || indentLeft != null) {
              writer.element(
                'w:spacing',
                attributes: <String, String>{
                  if (before != null) 'w:before': '$before',
                  if (after != null) 'w:after': '$after',
                },
              );
            }
            if (indentLeft != null) {
              writer.element(
                'w:ind',
                attributes: <String, String>{'w:left': '$indentLeft'},
              );
            }
            if (outlineLevel != null) {
              writer.element(
                'w:outlineLvl',
                attributes: <String, String>{'w:val': '$outlineLevel'},
              );
            }
          },
        );
        writer.element(
          'w:rPr',
          nest: () {
            if (font != null) {
              writer.element(
                'w:rFonts',
                attributes: <String, String>{'w:ascii': font, 'w:hAnsi': font},
              );
            }
            if (bold) {
              writer.element('w:b');
            }
            if (italic) {
              writer.element('w:i');
            }
            if (size != null) {
              writer.element(
                'w:sz',
                attributes: <String, String>{'w:val': '$size'},
              );
            }
          },
        );
      },
    );
  }

  void _writeCharacterStyle(
    XmlWriter writer, {
    required String id,
    required String name,
  }) {
    writer.element(
      'w:style',
      attributes: <String, String>{'w:type': 'character', 'w:styleId': id},
      nest: () {
        writer.element('w:name', attributes: <String, String>{'w:val': name});
        writer.element(
          'w:rPr',
          nest: () {
            writer.element(
              'w:vertAlign',
              attributes: <String, String>{'w:val': 'superscript'},
            );
          },
        );
      },
    );
  }
}
