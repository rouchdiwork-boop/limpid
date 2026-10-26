import '../util/xml_writer.dart';
import 'docx_package.dart';

/// Generateur de `word/footnotes.xml`.
class DocxFootnotesXml {
  const DocxFootnotesXml();

  /// Serialise les notes de bas de page.
  ///
  /// L'identifiant d'une note est son index dans [notes], plus un.
  String render(List<String> notes) {
    final writer = XmlWriter();
    writer.element(
      'w:footnotes',
      attributes: <String, String>{'xmlns:w': DocxPackage.wordNamespace},
      nest: () {
        _writeSeparator(writer, 'separator', -1);
        _writeSeparator(writer, 'continuationSeparator', 0);
        for (var index = 0; index < notes.length; index++) {
          _writeFootnote(writer, index + 1, notes[index]);
        }
      },
    );
    return writer.toXmlString();
  }

  void _writeSeparator(XmlWriter writer, String type, int id) {
    writer.element(
      'w:footnote',
      attributes: <String, String>{'w:type': type, 'w:id': '$id'},
      nest: () {
        writer.element(
          'w:p',
          nest: () {
            writer.element(
              'w:pPr',
              nest: () {
                writer.element(
                  'w:spacing',
                  attributes: <String, String>{
                    'w:after': '0',
                    'w:line': '240',
                    'w:lineRule': 'auto',
                  },
                );
              },
            );
            writer.element(
              'w:r',
              nest: () => writer.element(
                type == 'separator' ? 'w:separator' : 'w:continuationSeparator',
              ),
            );
          },
        );
      },
    );
  }

  void _writeFootnote(XmlWriter writer, int id, String text) {
    writer.element(
      'w:footnote',
      attributes: <String, String>{'w:id': '$id'},
      nest: () {
        writer.element(
          'w:p',
          nest: () {
            writer.element(
              'w:pPr',
              nest: () {
                writer.element(
                  'w:pStyle',
                  attributes: <String, String>{'w:val': 'FootnoteText'},
                );
              },
            );
            writer.element(
              'w:r',
              nest: () {
                writer.element(
                  'w:rPr',
                  nest: () {
                    writer.element(
                      'w:rStyle',
                      attributes: <String, String>{
                        'w:val': 'FootnoteReference',
                      },
                    );
                  },
                );
                writer.element('w:footnoteRef');
              },
            );
            writer.element(
              'w:r',
              nest: () {
                writer.element(
                  'w:t',
                  attributes: <String, String>{'xml:space': 'preserve'},
                  nest: () => writer.text(' $text'),
                );
              },
            );
          },
        );
      },
    );
  }
}
