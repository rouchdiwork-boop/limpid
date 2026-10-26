import '../model/export_book.dart';
import '../model/export_options.dart';
import 'pdf_barcode.dart';
import 'pdf_cover.dart';
import 'pdf_geometry.dart';
import 'pdf_page_content.dart';

/// La page de couverture d'un livre.
///
/// La couverture occupe la page entiere en lecture ; en impression, elle
/// occupe le format final, le fond perdu restant hors de la couverture.
///
/// En edition imprimee, la couverture porte le code-barres de l'ISBN :
/// l'imprimeur le cherche sur la couverture, pas seulement sur la page de
/// garde.
class PdfCoverPage {
  /// Cree une page de couverture.
  const PdfCoverPage({
    required this.geometry,
    required this.options,
    this.onWarning,
  });

  /// La geometrie des pages.
  final PdfPageGeometry geometry;

  /// Les options d'export.
  final ExportOptions options;

  /// Collecteur d'avertissements non bloquants.
  final void Function(String message)? onWarning;

  /// La page de couverture, ou `null` quand le livre n'en porte pas.
  ///
  /// Une couverture illisible est signalee puis abandonnee : l'export
  /// continue sans elle, plutot que de produire un fichier casse.
  PdfPageContent? build(ExportBook book) {
    if (!options.includeCoverImage) {
      return null;
    }
    final image = book.coverImage;
    if (image == null) {
      return null;
    }
    final cover = PdfCover.fromImage(image);
    if (cover == null) {
      onWarning?.call('Couverture ignoree : format illisible.');
      return null;
    }

    final box = _box();
    final width = _width(cover.aspectRatio, box.width, box.height);
    final height = width / cover.aspectRatio;
    final PdfCoverRun coverRun = PdfCoverRun(
      cover: cover,
      left: box.left + (box.width - width) / 2,
      top: box.top + (box.height - height) / 2,
      width: width,
      height: height,
    );
    return PdfPageContent(
      pageWidth: geometry.pageWidth,
      pageHeight: geometry.pageHeight,
      isEven: false,
      pageNumber: 0,
      texts: const <PdfTextRun>[],
      images: const <PdfImageRun>[],
      cover: coverRun,
      barcode: _barcode(book, coverRun),
    );
  }

  /// Le code-barres pose sur la couverture, quand l'edition imprimee en
  /// porte un.
  ///
  /// Le code est cale sur le bas de la couverture, au centre : il reste
  /// dans la zone imprimee, il ne deborde jamais de la couverture. Une
  /// couverture trop etroite pour le porter ne le porte pas : le code
  /// deborderait du papier.
  PdfBarcodeRun? _barcode(ExportBook book, PdfCoverRun cover) {
    final PdfBarcode? barcode = PdfBarcode.ofBook(
      book,
      mode: options.pdfMode,
      place: 'la couverture',
      onWarning: onWarning,
    );
    if (barcode == null) {
      return null;
    }
    if (barcode.width > cover.width) {
      onWarning?.call(
        'Couverture trop etroite pour le code-barres : le code-barres n a '
        'pas ete imprime sur la couverture.',
      );
      return null;
    }
    return PdfBarcodeRun(
      barcode: barcode,
      left: cover.left + (cover.width - barcode.width) / 2,
      top: cover.top + cover.height - barcode.height,
    );
  }

  /// Le rectangle qui recoit la couverture.
  _CoverBox _box() {
    if (options.pdfMode == ExportPdfMode.printReady) {
      return _CoverBox(
        left: geometry.trimLeft,
        top: geometry.trimTop,
        width: geometry.trimWidth,
        height: geometry.trimHeight,
      );
    }
    return _CoverBox(
      left: 0,
      top: 0,
      width: geometry.pageWidth,
      height: geometry.pageHeight,
    );
  }

  /// La largeur de la couverture, calee sur son rapport et le rectangle
  /// qui la recoit.
  double _width(double aspectRatio, double boxWidth, double boxHeight) {
    if (aspectRatio <= 0) {
      return boxWidth;
    }
    final byWidth = boxWidth;
    final byHeight = boxHeight * aspectRatio;
    return byHeight < byWidth ? byHeight : byWidth;
  }
}

/// Le rectangle qui recoit la couverture.
class _CoverBox {
  /// Cree un rectangle.
  const _CoverBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// L'abscisse du bord gauche.
  final double left;

  /// L'ordonnee du bord superieur.
  final double top;

  /// La largeur du rectangle.
  final double width;

  /// La hauteur du rectangle.
  final double height;
}
