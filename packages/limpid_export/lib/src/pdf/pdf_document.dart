import 'dart:convert';
import 'dart:typed_data';

/// Les dimensions et le nombre de pages d'un PDF produit par le moteur.
///
/// La lecture se fait sur le texte du fichier : les objets de page ne sont
/// pas compresses, le rectangle de la page (`MediaBox`) et le type des
/// pages s'y lisent directement.
final class PdfDocument {
  /// Cree une description.
  const PdfDocument({
    required this.pageCount,
    required this.mediaBoxWidth,
    required this.mediaBoxHeight,
  });

  /// Lit le document [bytes].
  ///
  /// Les dimensions valent `null` quand le rectangle de la page n'a pas pu
  /// etre lu : le fichier produit est alors inexploitable pour un imprimeur.
  static PdfDocument read(Uint8List bytes) {
    final String raw = latin1.decode(bytes, allowInvalid: true);
    final int pageCount = _pageObject.allMatches(raw).length;
    final RegExpMatch? box = _mediaBox.firstMatch(raw);
    if (box == null) {
      return PdfDocument(
        pageCount: pageCount,
        mediaBoxWidth: null,
        mediaBoxHeight: null,
      );
    }
    return PdfDocument(
      pageCount: pageCount,
      mediaBoxWidth: _number(box.group(3)) - _number(box.group(1)),
      mediaBoxHeight: _number(box.group(4)) - _number(box.group(2)),
    );
  }

  /// Le nombre de pages du document.
  final int pageCount;

  /// La largeur de la page, en points, `null` quand elle est illisible.
  final double? mediaBoxWidth;

  /// La hauteur de la page, en points, `null` quand elle est illisible.
  final double? mediaBoxHeight;

  /// Le nombre de points par millimetre.
  static const double pointsPerMm = 72 / 25.4;

  /// Le rectangle de la page, tel que le moteur l'ecrit.
  static final RegExp _mediaBox = RegExp(
    r'/MediaBox\s*\[\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*\]',
  );

  /// Le type des objets de page ; `/Type/Pages` est le repertoire, pas une
  /// page.
  static final RegExp _pageObject = RegExp(r'/Type\s*/Page(?![s])');

  static double _number(String? raw) => double.tryParse(raw ?? '') ?? 0;
}
