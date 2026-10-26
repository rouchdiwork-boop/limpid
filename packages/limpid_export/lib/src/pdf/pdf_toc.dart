import '../model/export_options.dart';
import 'pdf_fonts.dart';
import 'pdf_geometry.dart';
import 'pdf_page_content.dart';
import 'pdf_page_draft.dart';
import 'pdf_text_measure.dart';

/// Entree de table des matieres.
class PdfTocEntry {
  /// Cree une entree de table des matieres.
  const PdfTocEntry({
    required this.title,
    required this.pageNumber,
    required this.destination,
  });

  /// Titre du chapitre.
  final String title;

  /// Numero de page du chapitre.
  final int pageNumber;

  /// Destination interne liee au chapitre.
  final String destination;
}

/// Nom de la destination interne d'un chapitre (sommaire cliquable).
String chapterDestination(int index) => 'chapitre-${index + 1}';

/// Mise en page de la table des matieres.
class PdfTocWriter {
  /// Cree un redacteur de table des matieres.
  const PdfTocWriter({
    required this.geometry,
    required this.measure,
    required this.fonts,
    required this.options,
  });

  /// Geometrie des pages.
  final PdfPageGeometry geometry;

  /// Mesure du texte.
  final PdfTextMeasure measure;

  /// Polices utilisees.
  final PdfFontSet fonts;

  /// Options d'export.
  final ExportOptions options;

  /// Titre de la table des matieres.
  static const String title = 'Table des matieres';

  /// Compose les pages de la table des matieres.
  List<PdfPageContent> layout(List<PdfTocEntry> entries) {
    final state = PdfPaginationState(geometry);
    final titleFont = fonts.select(isBold: true, isItalic: false);
    final bodyFont = fonts.select(isBold: false, isItalic: false);
    final titleSize = options.fontSize * 1.5;
    final bodySize = options.fontSize;
    final leading = bodySize * options.lineHeight;
    final contentBottom = geometry.contentTop() + geometry.contentHeight();

    state.startPage(chapterIndex: -1);
    var cursor = geometry.contentTop() + geometry.contentHeight() * 0.08;

    state.addText(
      PdfTextRun(
        text: measure.sanitize(title, titleFont),
        left: geometry.contentLeft(false),
        top: cursor,
        fontSize: titleSize,
        font: titleFont,
      ),
    );
    cursor += titleSize * 1.8;

    for (final entry in entries) {
      if (cursor + leading > contentBottom) {
        state.startPage(chapterIndex: -1);
        cursor = geometry.contentTop();
      }
      final isEven = state.current!.isEven;
      final contentLeft = geometry.contentLeft(isEven);
      final contentWidth = geometry.contentWidth(isEven);
      final numberText = '${entry.pageNumber}';
      final numberWidth = measure.widthOf(numberText, bodyFont, bodySize);
      state.addText(
        PdfTextRun(
          text: measure.sanitize(entry.title, bodyFont),
          left: contentLeft,
          top: cursor,
          fontSize: bodySize,
          font: bodyFont,
          linkDestination: entry.destination,
        ),
      );
      state.addText(
        PdfTextRun(
          text: numberText,
          left: contentLeft + contentWidth - numberWidth,
          top: cursor,
          fontSize: bodySize,
          font: bodyFont,
          linkDestination: entry.destination,
        ),
      );
      cursor += leading;
    }

    return state.pages;
  }
}
