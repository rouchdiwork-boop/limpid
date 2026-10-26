import 'pdf_geometry.dart';
import 'pdf_page_content.dart';

/// Brouillon de page, utilise pendant la pagination.
///
/// Les blocs y sont ajoutes au fur et a mesure ; la conversion en
/// [PdfPageContent] a lieu a la fin de la pagination.
class PdfPageDraft {
  /// Cree un brouillon de page.
  PdfPageDraft({
    required this.pageWidth,
    required this.pageHeight,
    required this.isEven,
    required this.pageNumber,
    required this.chapterIndex,
  });

  /// Largeur de la page, en points.
  final double pageWidth;

  /// Hauteur de la page, en points.
  final double pageHeight;

  /// Vrai si la page est verso (numero pair).
  final bool isEven;

  /// Numero de page dans le corps du document.
  final int pageNumber;

  /// Index du chapitre courant (-1 pour les pages liminaires).
  final int chapterIndex;

  /// Blocs de texte positionnes.
  final List<PdfTextRun> texts = <PdfTextRun>[];

  /// Illustrations positionnees.
  final List<PdfImageRun> images = <PdfImageRun>[];

  /// Convertit le brouillon en page finale.
  PdfPageContent toContent() {
    return PdfPageContent(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      isEven: isEven,
      pageNumber: pageNumber,
      texts: List<PdfTextRun>.unmodifiable(texts),
      images: List<PdfImageRun>.unmodifiable(images),
      chapterIndex: chapterIndex,
    );
  }
}

/// Etat de la pagination : pages produites et page en cours.
class PdfPaginationState {
  /// Cree un etat de pagination.
  PdfPaginationState(this.geometry);

  /// Geometrie des pages.
  final PdfPageGeometry geometry;

  /// Brouillons de pages, dans l'ordre.
  final List<PdfPageDraft> drafts = <PdfPageDraft>[];

  /// Page en cours de remplissage.
  PdfPageDraft? current;

  /// Position verticale courante, relative au haut du bloc de texte.
  double cursor = 0;

  /// Pages finales.
  List<PdfPageContent> get pages =>
      drafts.map((draft) => draft.toContent()).toList(growable: false);

  /// Demarre une nouvelle page.
  void startPage({required int chapterIndex}) {
    final pageIndex = drafts.length;
    current = PdfPageDraft(
      pageWidth: geometry.pageWidth,
      pageHeight: geometry.pageHeight,
      isEven: pageIndex % 2 != 0,
      pageNumber: pageIndex + 1,
      chapterIndex: chapterIndex,
    );
    drafts.add(current!);
    cursor = 0;
  }

  /// Ajoute un bloc de texte a la page courante.
  void addText(PdfTextRun run) {
    current!.texts.add(run);
  }

  /// Ajoute une illustration a la page courante.
  void addImage(PdfImageRun run) {
    current!.images.add(run);
  }
}
