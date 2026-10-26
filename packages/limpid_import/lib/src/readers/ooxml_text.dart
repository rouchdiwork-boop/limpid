import 'package:xml/xml.dart';

/// Les elements OOXML qui ne portent pas de texte de manuscrit.
///
/// Les proprietes de paragraphe et de run ne contiennent pas de prose, et
/// les dessins contiennent un texte de remplacement qui n'est pas le texte
/// de l'auteur.
const Set<String> ooxmlPropertyElements = <String>{
  'pPr',
  'rPr',
  'sectPr',
  'tblPr',
  'trPr',
  'tcPr',
  'drawing',
  'pict',
  'object',
  'AlternateContent',
};

/// Le texte d'un element OOXML (le vocabulaire de Word).
///
/// Les runs d'un paragraphe sont eparpilles : un texte peut etre coupe par
/// une tabulation, un saut de ligne ou un dessin. La lecture se fait donc
/// dans l ordre du document, et non element par element.
String ooxmlTextOf(XmlElement element, {Set<String> skipped = const {}}) {
  final StringBuffer buffer = StringBuffer();

  void walk(XmlElement node) {
    for (final XmlNode child in node.children) {
      if (child is! XmlElement) continue;
      final String name = child.name.local;
      if (skipped.contains(name)) continue;
      if (ooxmlPropertyElements.contains(name)) continue;
      switch (name) {
        case 't':
          buffer.write(child.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br':
        case 'cr':
          buffer.write('\n');
        case 'noBreakHyphen':
          buffer.write('-');
        case 'softHyphen':
        case 'sym':
          break;
        default:
          walk(child);
      }
    }
  }

  walk(element);
  return buffer.toString();
}
