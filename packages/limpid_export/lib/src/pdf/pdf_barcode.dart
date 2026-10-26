import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../barcode/ean13.dart';
import '../model/export_book.dart';
import '../model/export_options.dart';
import 'pdf_geometry.dart';

/// Le code-barres EAN-13 dessine sur une page PDF.
///
/// Le symbole est rendu en vecteurs : une barre par suite de modules, puis
/// les chiffres sous les barres, comme sur un livre imprime. Les
/// dimensions suivent la norme EAN-13 : un module de 0,33 mm, des barres
/// de 22,85 mm, et des zones de silence de 11 et 7 modules.
class PdfBarcode {
  /// Cree un code-barres pour un symbole EAN-13.
  const PdfBarcode({
    required this.symbol,
    this.moduleWidthMm = 0.33,
    this.barHeightMm = 22.85,
  });

  /// Le symbole encode.
  final Ean13 symbol;

  /// Largeur d'un module, en millimetres.
  final double moduleWidthMm;

  /// Hauteur des barres, en millimetres.
  final double barHeightMm;

  /// Avance d'un caractere de Courier, contre sa taille.
  ///
  /// Courier est monospace : tous ses caracteres occupent 600 millièmes de
  /// la taille de police.
  static const double courierAdvanceRatio = 0.6;

  /// Hauteur du bloc des chiffres, en rapport de la taille de police.
  ///
  /// La police reserves un peu plus que sa taille : le bloc accueille la
  /// chasse et la descente.
  static const double digitBlockRatio = 1.2;

  /// La largeur du symbole, zones de silence comprises, en points.
  double get width => Ean13.totalWidth * moduleWidth;

  /// La hauteur du symbole, chiffres compris, en points.
  double get height =>
      (barHeightMm * PdfPageGeometry.pointsPerMm) + digitBlockHeight;

  /// La largeur d'un module, en points.
  double get moduleWidth => moduleWidthMm * PdfPageGeometry.pointsPerMm;

  /// La taille des chiffres, calculee pour qu'un chiffre occupe les sept
  /// modules du code qu'il encode.
  ///
  /// La norme imprime les chiffres en OCR-B, une police condensee que le
  /// moteur PDF ne livre pas ; les chiffres sont donc poses sur la largeur
  /// de leur code, ce qui les aligne sur les barres.
  double get digitFontSize =>
      (Ean13.digitModules * moduleWidth) / courierAdvanceRatio;

  /// La hauteur du bloc des chiffres, en points.
  double get digitBlockHeight => digitFontSize * digitBlockRatio;

  /// Le code-barres du livre [book], quand l'édition imprimée en porte un.
  ///
  /// Le code n'apparait que si le mode est l'impression et que l'ISBN est
  /// present et valide : un code-barres n'est jamais fabrique a partir
  /// d'une autre valeur. Son absence n'est pas une erreur, elle est
  /// signalee a [onWarning] avec le nom de l'emplacement qui ne porte pas
  /// de code.
  static PdfBarcode? ofBook(
    ExportBook book, {
    required ExportPdfMode mode,
    required String place,
    void Function(String message)? onWarning,
  }) {
    if (mode != ExportPdfMode.printReady) {
      return null;
    }

    final String? isbn = book.metadata.isbn;
    if (isbn == null || isbn.trim().isEmpty) {
      onWarning?.call(
        'Aucun ISBN : le code-barres n a pas ete imprime sur $place.',
      );
      return null;
    }
    final Ean13? symbol = Ean13.tryParse(isbn);
    if (symbol == null) {
      onWarning?.call(
        'ISBN invalide ($isbn) : le code-barres n a pas ete imprime sur '
        '$place.',
      );
      return null;
    }
    return PdfBarcode(symbol: symbol);
  }

  /// Construit le widget du code-barres.
  pw.Widget build() {
    final module = moduleWidth;
    final barHeight = barHeightMm * PdfPageGeometry.pointsPerMm;
    final totalWidth = width;

    return pw.SizedBox(
      width: totalWidth,
      height: height,
      child: pw.Stack(
        children: <pw.Widget>[
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.CustomPaint(
              size: PdfPoint(totalWidth, barHeight),
              painter: _paintBars,
            ),
          ),
          ..._digits(module, barHeight),
        ],
      ),
    );
  }

  void _paintBars(PdfGraphics canvas, PdfPoint size) {
    final module = moduleWidth;
    canvas.setFillColor(PdfColors.black);
    for (final run in symbol.runs) {
      final left = (Ean13.leftQuietZone + run.start) * module;
      canvas.drawRect(left, 0, run.length * module, size.y);
    }
    canvas.fillPath();
  }

  List<pw.Widget> _digits(double module, double barHeight) {
    final style = pw.TextStyle(
      font: pw.Font.courier(),
      fontSize: digitFontSize,
      color: PdfColors.black,
    );
    final digits = symbol.digits;

    // Le premier chiffre est imprime dans la zone de silence, a gauche du
    // garde ; les deux groupes sont alignes sur le garde central.
    final leading = pw.Positioned(
      left: 0,
      top: barHeight,
      child: pw.Text(digits.substring(0, 1), style: style),
    );
    final leftGroup = pw.Positioned(
      left:
          (Ean13.leftQuietZone + Ean13.leftGuardStart + Ean13.guardLength) *
          module,
      top: barHeight,
      child: pw.Text(digits.substring(1, 7), style: style),
    );
    final rightGroup = pw.Positioned(
      left:
          (Ean13.leftQuietZone +
              Ean13.centerGuardStart +
              Ean13.centerGuardLength) *
          module,
      top: barHeight,
      child: pw.Text(digits.substring(7), style: style),
    );
    return <pw.Widget>[leading, leftGroup, rightGroup];
  }
}
