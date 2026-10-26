/// Namespaces XML utilises par le format OpenDocument.
class OdtNamespaces {
  const OdtNamespaces._();

  /// Namespace `office`.
  static const String office =
      'urn:oasis:names:tc:opendocument:xmlns:office:1.0';

  /// Namespace `text`.
  static const String text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

  /// Namespace `style`.
  static const String style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

  /// Namespace `fo` (compatibilite XSL).
  static const String fo =
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

  /// Namespace `dc` (Dublin Core).
  static const String dc = 'http://purl.org/dc/elements/1.1/';

  /// Namespace `meta`.
  static const String meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

  /// Namespace `xlink`.
  static const String xlink = 'http://www.w3.org/1999/xlink';

  /// Namespace `draw`.
  static const String draw =
      'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';

  /// Namespace `svg`.
  static const String svg =
      'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';

  /// Namespace `number`.
  static const String number =
      'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0';

  /// Toutes les namespaces, associees a leur prefixe.
  static const Map<String?, String> all = <String?, String>{
    'office': office,
    'text': text,
    'style': style,
    'fo': fo,
    'dc': dc,
    'meta': meta,
    'xlink': xlink,
    'draw': draw,
    'svg': svg,
    'number': number,
  };

  /// Type MIME du paquet ODT.
  static const String mimeType = 'application/vnd.oasis.opendocument.text';
}
