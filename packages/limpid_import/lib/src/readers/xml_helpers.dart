import 'package:xml/xml.dart';

/// The value of the attribute [name] of [element], whatever its namespace.
///
/// Les documents OOXML et ODF utilisent un prefixe pour leurs attributs,
/// mais le prefixe change d'un producteur a l'autre : c'est le nom local
/// qui compte.
String? attributeOf(XmlElement element, String name) {
  return element.getAttribute(name, namespaceUri: '*');
}

/// The first direct child of [element] named [name], `null` when there is
/// none.
XmlElement? childOf(XmlElement element, String name) {
  for (final XmlNode child in element.children) {
    if (child is! XmlElement) continue;
    if (child.name.local == name) return child;
  }
  return null;
}

/// The first descendant of [element] named [name], `null` when there is
/// none.
XmlElement? descendantNamed(XmlElement element, String name) {
  for (final XmlNode child in element.descendants) {
    if (child is! XmlElement) continue;
    if (child.name.local == name) return child;
  }
  return null;
}

/// The direct children of [element] named [name].
List<XmlElement> childrenNamed(XmlElement element, String name) {
  return element.children
      .whereType<XmlElement>()
      .where((XmlElement child) => child.name.local == name)
      .toList(growable: false);
}
