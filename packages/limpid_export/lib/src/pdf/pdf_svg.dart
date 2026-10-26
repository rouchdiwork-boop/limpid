import 'package:xml/xml.dart';

/// Un document SVG prepare pour le moteur PDF.
///
/// L'interpreteur SVG du moteur PDF ne rend pas les filtres : un element
/// qui s'appuie sur un filtre y serait interprete comme un aplat. La
/// preparation retire ces elements — les couvertures generees n'y
/// placent qu'un grain — ainsi que les definitions de filtres devenues
/// inutiles. Le reste du document, y compris son degrade, est rendu en
/// vecteurs.
class PdfSvg {
  /// Cree un document SVG prepare.
  const PdfSvg({
    required this.source,
    required this.width,
    required this.height,
  });

  /// Le document SVG, debarrasse des constructions non rendues.
  final String source;

  /// La largeur du document, dans son propre systeme d'unites.
  final double width;

  /// La hauteur du document, dans son propre systeme d'unites.
  final double height;

  /// Le rapport largeur / hauteur du document.
  double get aspectRatio => height == 0 ? 1 : width / height;

  /// Prepare un document SVG pour le moteur PDF.
  ///
  /// Renvoie `null` quand le document ne peut pas etre lu : le moteur PDF
  /// ne saurait pas le dessiner non plus.
  static PdfSvg? prepare(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException {
      return null;
    }

    final root = document.rootElement;
    final size = _sizeOf(root);
    _removeFilteredElements(root);
    return PdfSvg(
      source: document.toXmlString(),
      width: size.$1,
      height: size.$2,
    );
  }

  /// Retire les elements qui s'appuient sur un filtre, puis les
  /// definitions de filtres.
  static void _removeFilteredElements(XmlElement root) {
    final filtered = root.descendants
        .whereType<XmlElement>()
        .where((element) => element.getAttribute('filter') != null)
        .toList(growable: false);
    for (final element in filtered) {
      element.remove();
    }

    final definitions = root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'filter')
        .toList(growable: false);
    for (final definition in definitions) {
      definition.remove();
    }
  }

  /// Les dimensions du document, lues dans sa `viewBox` ou, a defaut,
  /// dans ses attributs `width` et `height`.
  static (double, double) _sizeOf(XmlElement root) {
    final viewBox = root.getAttribute('viewBox');
    if (viewBox != null) {
      final parts = <double>[];
      for (final part in viewBox.split(RegExp(r'[\s,]+'))) {
        final value = double.tryParse(part);
        if (value != null) {
          parts.add(value);
        }
      }
      if (parts.length == 4 && parts[2] > 0 && parts[3] > 0) {
        return (parts[2], parts[3]);
      }
    }
    final width = _numeric(root.getAttribute('width'));
    final height = _numeric(root.getAttribute('height'));
    return (width, height);
  }

  /// Lit une dimension SVG, en ignorant son unite.
  static double _numeric(String? raw) {
    if (raw == null) {
      return 0;
    }
    final match = RegExp(r'[-+]?[0-9]*\.?[0-9]+').firstMatch(raw);
    return match == null ? 0 : double.parse(match.group(0)!);
  }
}
