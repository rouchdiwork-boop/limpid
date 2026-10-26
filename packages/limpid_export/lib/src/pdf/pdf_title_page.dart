import '../model/export_book.dart';
import '../model/export_options.dart';
import 'pdf_barcode.dart';
import 'pdf_fonts.dart';
import 'pdf_geometry.dart';
import 'pdf_page_content.dart';
import 'pdf_text_measure.dart';

/// La page de garde d'un livre.
///
/// La page porte le titre, le sous-titre et les auteurs. En edition
/// imprimee, elle porte aussi le code-barres EAN-13 de l'ISBN : c'est la
/// que l'imprimeur le cherche.
class PdfTitlePage {
  /// Cree une page de garde.
  const PdfTitlePage({
    required this.geometry,
    required this.measure,
    required this.fonts,
    required this.options,
    this.onWarning,
  });

  /// La geometrie des pages.
  final PdfPageGeometry geometry;

  /// La mesure du texte.
  final PdfTextMeasure measure;

  /// Les polices utilisees.
  final PdfFontSet fonts;

  /// Les options d'export.
  final ExportOptions options;

  /// Collecteur d'avertissements non bloquants.
  final void Function(String message)? onWarning;

  /// La page de garde du livre.
  PdfPageContent build(ExportBook book) {
    const isEven = false;
    final contentWidth = geometry.contentWidth(isEven);
    final contentLeft = geometry.contentLeft(isEven);
    final center = contentLeft + contentWidth / 2;
    final titleSize = options.fontSize * 2.1;
    final subtitleSize = options.fontSize * 1.25;
    final authorSize = options.fontSize * 1.05;

    final texts = <PdfTextRun>[];
    var y = geometry.contentTop() + geometry.contentHeight() * 0.28;

    final titleFont = fonts.select(isBold: true, isItalic: false);
    for (final line in measure.wrap(
      book.title,
      titleFont,
      titleSize,
      contentWidth * 0.86,
    )) {
      final lineWidth = measure.widthOf(line.text, titleFont, titleSize);
      texts.add(
        PdfTextRun(
          text: measure.sanitize(line.text, titleFont),
          left: center - lineWidth / 2,
          top: y,
          fontSize: titleSize,
          font: titleFont,
        ),
      );
      y += titleSize * 1.25;
    }

    final subtitle = book.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      y += subtitleSize * 1.4;
      final subtitleFont = fonts.select(isBold: false, isItalic: true);
      for (final line in measure.wrap(
        subtitle,
        subtitleFont,
        subtitleSize,
        contentWidth * 0.8,
      )) {
        final lineWidth = measure.widthOf(
          line.text,
          subtitleFont,
          subtitleSize,
        );
        texts.add(
          PdfTextRun(
            text: measure.sanitize(line.text, subtitleFont),
            left: center - lineWidth / 2,
            top: y,
            fontSize: subtitleSize,
            font: subtitleFont,
          ),
        );
        y += subtitleSize * 1.35;
      }
    }

    if (book.authors.isNotEmpty) {
      y += authorSize * 2;
      final authorFont = fonts.select(isBold: false, isItalic: false);
      final authors = book.authors.join(', ');
      final lineWidth = measure.widthOf(authors, authorFont, authorSize);
      texts.add(
        PdfTextRun(
          text: measure.sanitize(authors, authorFont),
          left: center - lineWidth / 2,
          top: y,
          fontSize: authorSize,
          font: authorFont,
        ),
      );
    }

    return PdfPageContent(
      pageWidth: geometry.pageWidth,
      pageHeight: geometry.pageHeight,
      isEven: isEven,
      pageNumber: 1,
      texts: texts,
      images: const <PdfImageRun>[],
      barcode: _barcode(book),
    );
  }

  /// Le code-barres de la page de garde, quand l'edition imprimee en
  /// porte un.
  ///
  /// Le code n'apparait que si l'ISBN est present et valide. Son absence
  /// n'est pas une erreur : elle est signalee, pour que l'export dise
  /// clairement ce qui manque.
  PdfBarcodeRun? _barcode(ExportBook book) {
    final barcode = PdfBarcode.ofBook(
      book,
      mode: options.pdfMode,
      place: 'la page de garde',
      onWarning: onWarning,
    );
    if (barcode == null) {
      return null;
    }

    final contentWidth = geometry.contentWidth(false);
    return PdfBarcodeRun(
      barcode: barcode,
      left: geometry.contentLeft(false) + (contentWidth - barcode.width) / 2,
      top: geometry.contentTop() + geometry.contentHeight() - barcode.height,
    );
  }
}
