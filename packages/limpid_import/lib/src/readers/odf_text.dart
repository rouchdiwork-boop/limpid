import 'package:xml/xml.dart';

/// Le texte d'un element ODF (le vocabulaire de LibreOffice).
///
/// Le texte ODF n'est jamais d'un seul tenant : les espaces sont des
/// elements (`text:s`), les tabulations ont leur element, et les notes de
/// bas de page sont des sous-elements qui ne font pas partie du texte de
/// l'auteur.
String odfTextOf(XmlElement element, {Set<String> skipped = const {}}) {
  final StringBuffer buffer = StringBuffer();

  void walk(XmlElement node) {
    for (final XmlNode child in node.children) {
      if (child is XmlText) {
        buffer.write(child.value);
        continue;
      }
      if (child is! XmlElement) continue;
      final String name = child.name.local;
      if (skipped.contains(name)) continue;
      switch (name) {
        case 's':
          buffer.write(' ' * _countOf(child));
        case 'tab':
          buffer.write('\t');
        case 'line-break':
          buffer.write('\n');
        case 'note':
        case 'annotation':
          break;
        case 'bookmark':
        case 'bookmark-start':
        case 'bookmark-end':
          break;
        default:
          walk(child);
      }
    }
  }

  walk(element);
  return buffer.toString();
}

/// The number of spaces an element `text:s` stands for.
int _countOf(XmlElement element) {
  final String? raw = element.getAttribute('c', namespaceUri: '*');
  final int? count = raw == null ? null : int.tryParse(raw);
  if (count == null || count < 1) return 1;
  return count;
}
