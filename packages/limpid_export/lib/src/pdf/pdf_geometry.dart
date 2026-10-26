import '../model/export_options.dart';

/// Geometrie d'une page PDF.
///
/// Les distances sont exprimees en points (72 par pouce). Le format final
/// (`trim`) peut etre entoure d'un fond perdu (`bleed`), ce qui est la
/// convention de l'impression professionnelle.
class PdfPageGeometry {
  /// Cree une geometrie de page.
  const PdfPageGeometry({
    required this.pageWidth,
    required this.pageHeight,
    required this.trimLeft,
    required this.trimTop,
    required this.trimWidth,
    required this.trimHeight,
    required this.marginInside,
    required this.marginOutside,
    required this.marginTop,
    required this.marginBottom,
    required this.isMirrored,
  });

  /// Nombre de points par millimetre.
  static const double pointsPerMm = 72 / 25.4;

  /// Largeur totale de la page, fond perdu compris.
  final double pageWidth;

  /// Hauteur totale de la page, fond perdu compris.
  final double pageHeight;

  /// Distance entre le bord gauche de la page et le bord gauche du format
  /// final.
  final double trimLeft;

  /// Distance entre le bord haut de la page et le bord haut du format final.
  final double trimTop;

  /// Largeur du format final.
  final double trimWidth;

  /// Hauteur du format final.
  final double trimHeight;

  /// Marge interieure (reliure).
  final double marginInside;

  /// Marge exterieure.
  final double marginOutside;

  /// Marge haute.
  final double marginTop;

  /// Marge basse.
  final double marginBottom;

  /// Vrai si les marges sont en miroir (page paire : reliure a droite).
  final bool isMirrored;

  /// Construit la geometrie a partir des options d'export.
  factory PdfPageGeometry.fromOptions(ExportOptions options) {
    if (options.pdfMode == ExportPdfMode.printReady) {
      final bleed = options.bleedMm * pointsPerMm;
      return PdfPageGeometry(
        pageWidth: options.trimWidthMm * pointsPerMm + bleed * 2,
        pageHeight: options.trimHeightMm * pointsPerMm + bleed * 2,
        trimLeft: bleed,
        trimTop: bleed,
        trimWidth: options.trimWidthMm * pointsPerMm,
        trimHeight: options.trimHeightMm * pointsPerMm,
        marginInside: options.marginInsideMm * pointsPerMm,
        marginOutside: options.marginOutsideMm * pointsPerMm,
        marginTop: options.marginTopMm * pointsPerMm,
        marginBottom: options.marginBottomMm * pointsPerMm,
        isMirrored: true,
      );
    }
    return PdfPageGeometry(
      pageWidth: options.pageWidthMm * pointsPerMm,
      pageHeight: options.pageHeightMm * pointsPerMm,
      trimLeft: 0,
      trimTop: 0,
      trimWidth: options.pageWidthMm * pointsPerMm,
      trimHeight: options.pageHeightMm * pointsPerMm,
      marginInside: options.marginInsideMm * pointsPerMm,
      marginOutside: options.marginOutsideMm * pointsPerMm,
      marginTop: options.marginTopMm * pointsPerMm,
      marginBottom: options.marginBottomMm * pointsPerMm,
      isMirrored: true,
    );
  }

  /// Marge gauche du bloc de texte pour une page donnee.
  ///
  /// [isEven] vaut vrai pour une page verso (numero pair).
  double leftMargin(bool isEven) {
    if (!isMirrored) {
      return marginInside;
    }
    return isEven ? marginOutside : marginInside;
  }

  /// Marge droite du bloc de texte pour une page donnee.
  double rightMargin(bool isEven) {
    if (!isMirrored) {
      return marginOutside;
    }
    return isEven ? marginInside : marginOutside;
  }

  /// Abscisse du bloc de texte, relative a la page.
  double contentLeft(bool isEven) => trimLeft + leftMargin(isEven);

  /// Largeur du bloc de texte.
  double contentWidth(bool isEven) =>
      trimWidth - leftMargin(isEven) - rightMargin(isEven);

  /// Ordonnee du bloc de texte, relative a la page.
  double contentTop() => trimTop + marginTop;

  /// Hauteur du bloc de texte.
  double contentHeight() => trimHeight - marginTop - marginBottom;

  /// Position verticale du pied de page (base de la zone de texte).
  double footerBaseline() => trimTop + trimHeight - marginBottom + 24;

  /// Position verticale du titre courant.
  double headerBaseline() => trimTop + marginTop - 18;
}
