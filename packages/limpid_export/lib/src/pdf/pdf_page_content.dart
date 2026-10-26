import 'dart:typed_data';

import 'pdf_fonts.dart';

/// Bloc de texte positionne sur une page.
class PdfTextRun {
  /// Cree un bloc de texte positionne.
  const PdfTextRun({
    required this.text,
    required this.left,
    required this.top,
    required this.fontSize,
    required this.font,
    this.wordSpacing = 0,
    this.linkDestination,
  });

  /// Texte rendu.
  final String text;

  /// Abscisse de departure, en points, relative a la page.
  final double left;

  /// Ordonnee de depart, en points, relative a la page.
  final double top;

  /// Taille de police, en points.
  final double fontSize;

  /// Police utilisee.
  final PdfFontVariant font;

  /// Espacement supplementaire entre les mots (justification), en points.
  final double wordSpacing;

  /// Destination interne liee au texte (sommaire cliquable).
  final String? linkDestination;
}

/// Illustration positionnee sur une page.
class PdfImageRun {
  /// Cree une illustration positionnee.
  const PdfImageRun({
    required this.bytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Octets de l'image.
  final Uint8List bytes;

  /// Abscisse de departure, en points.
  final double left;

  /// Ordonnee de departure, en points.
  final double top;

  /// Largeur affichee, en points.
  final double width;

  /// Hauteur affichee, en points.
  final double height;
}

/// Contenu d'une page PDF, pre-positionne.
class PdfPageContent {
  /// Cree un contenu de page.
  PdfPageContent({
    required this.pageWidth,
    required this.pageHeight,
    required this.isEven,
    required this.pageNumber,
    required this.texts,
    required this.images,
    this.headerText,
    this.chapterIndex = -1,
  });

  /// Largeur de la page, en points.
  final double pageWidth;

  /// Hauteur de la page, en points.
  final double pageHeight;

  /// Vrai si la page est verso (numero pair).
  final bool isEven;

  /// Numero de page affiche.
  final int pageNumber;

  /// Blocs de texte positionnes.
  final List<PdfTextRun> texts;

  /// Illustrations positionnees.
  final List<PdfImageRun> images;

  /// Texte du titre courant, si demande.
  final String? headerText;

  /// Index du chapitre courant (-1 pour les pages liminaires).
  final int chapterIndex;

  /// Copie immuable avec un nouveau numero de page.
  PdfPageContent withPageNumber(int number) {
    return PdfPageContent(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      isEven: isEven,
      pageNumber: number,
      texts: texts,
      images: images,
      headerText: headerText,
      chapterIndex: chapterIndex,
    );
  }
}

/// Resultat d'une pagination.
class PdfPaginationResult {
  /// Cree un resultat de pagination.
  const PdfPaginationResult({
    required this.pages,
    required this.chapterPageNumbers,
    required this.chapterTitles,
  });

  /// Pages produites, dans l'ordre.
  final List<PdfPageContent> pages;

  /// Numero de page affiche de chaque chapitre, par index de chapitre.
  final List<int> chapterPageNumbers;

  /// Titres des chapitres, par index de chapitre.
  final List<String> chapterTitles;
}
