import '../util/xml_writer.dart';
import 'docx_package.dart';

/// Generateur de `word/numbering.xml` (listes a puces).
class DocxNumberingXml {
  const DocxNumberingXml();

  /// Numero de liste utilise pour les puces.
  static const int bulletNumberId = 1;

  /// Code du caractere puce de premier niveau (zone d'usage privee, police
  /// Symbol).
  static const int _bulletCode = 0xF0B7;

  /// Code du caractere puce de troisieme niveau (zone d'usage privee, police
  /// Symbol).
  static const int _squareCode = 0xF0A7;

  /// Serialise la definition de liste.
  String render() {
    final writer = XmlWriter();
    writer.element(
      'w:numbering',
      attributes: <String, String>{'xmlns:w': DocxPackage.wordNamespace},
      nest: () {
        writer.element(
          'w:abstractNum',
          attributes: <String, String>{'w:abstractNumId': '0'},
          nest: () {
            writer.element(
              'w:multiLevelType',
              attributes: <String, String>{'w:val': 'hybridMultilevel'},
            );
            for (var level = 0; level < 3; level++) {
              writer.element(
                'w:lvl',
                attributes: <String, String>{'w:ilvl': '$level'},
                nest: () {
                  writer.element(
                    'w:start',
                    attributes: <String, String>{'w:val': '1'},
                  );
                  writer.element(
                    'w:numFmt',
                    attributes: <String, String>{'w:val': 'bullet'},
                  );
                  writer.element(
                    'w:lvlText',
                    attributes: <String, String>{'w:val': _bulletFor(level)},
                  );
                  writer.element(
                    'w:lvlJc',
                    attributes: <String, String>{'w:val': 'left'},
                  );
                  writer.element(
                    'w:pPr',
                    nest: () {
                      writer.element(
                        'w:ind',
                        attributes: <String, String>{
                          'w:left': '${720 * (level + 1)}',
                          'w:hanging': '360',
                        },
                      );
                    },
                  );
                  writer.element(
                    'w:rPr',
                    nest: () {
                      writer.element(
                        'w:rFonts',
                        attributes: <String, String>{
                          'w:ascii': 'Symbol',
                          'w:hAnsi': 'Symbol',
                        },
                      );
                    },
                  );
                },
              );
            }
          },
        );
        writer.element(
          'w:num',
          attributes: <String, String>{'w:numId': '$bulletNumberId'},
          nest: () {
            writer.element(
              'w:abstractNumId',
              attributes: <String, String>{'w:val': '0'},
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  static String _bulletFor(int level) {
    switch (level) {
      case 0:
        return String.fromCharCode(_bulletCode);
      case 1:
        return 'o';
      default:
        return String.fromCharCode(_squareCode);
    }
  }
}
