import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';

import '../db/kdp_record.dart';
import 'kdp_metadata.dart';

/// Les exigences qu'Amazon applique à un livre déposé sur KDP.
///
/// Les valeurs viennent des consignes de publication d'Amazon : le format
/// imprimé est le 6 x 9 pouces, le fond perdu vaut 0,125 pouce, les marges
/// ne peuvent pas descendre sous 0,375 pouce, l'ouvrage imprimé compte au
/// moins 24 pages et le livre électronique au moins 5 000 mots.
abstract final class KdpRequirements {
  /// La largeur du format imprimé, en millimètres (6 pouces).
  static const double trimWidthMm = 152.4;

  /// La hauteur du format imprimé, en millimètres (9 pouces).
  static const double trimHeightMm = 228.6;

  /// Le fond perdu demandé par Amazon, en millimètres (0,125 pouce).
  static const double bleedMm = 3.2;

  /// La marge minimale acceptée, en millimètres (0,375 pouce).
  static const double minMarginMm = 9.6;

  /// Le nombre de pages minimal d'un ouvrage imprimé.
  static const int minPageCount = 24;

  /// Le nombre de mots minimal d'un livre électronique.
  static const int minWordCount = 5000;

  /// La tolérance de mesure, en millimètres.
  ///
  /// Les dimensions sont arrondies : une marge qui manque d'un centième de
  /// millimètre n'est pas un défaut d'impression.
  static const double toleranceMm = 0.05;
}

/// Les options d'impression qu'Amazon KDP accepte.
///
/// Le préréglage `ExportOptions.printReady` du moteur ne porte que 3 mm de
/// fond perdu ; Amazon en exige 0,125 pouce, soit 3,2 mm.
final ExportOptions kdpPrintOptions = ExportOptions.printReady.copyWith(
  bleedMm: KdpRequirements.bleedMm,
);

/// Le résultat du contrôle de soumission.
///
/// Le contrôle ne rend pas un booléen : il rend la liste des problèmes et
/// les mesures du dossier, que la trace conserve.
final class KdpSubmissionReport {
  /// Crée un rapport.
  const KdpSubmissionReport({
    required this.issues,
    required this.wordCount,
    required this.pageCount,
  });

  /// Les problèmes relevés.
  final List<KdpIssue> issues;

  /// Le nombre de mots du livre.
  final int wordCount;

  /// Le nombre de pages du PDF d'impression.
  final int pageCount;

  /// Vrai quand aucun problème n'empêche la soumission.
  bool get isReady => !issues.any((KdpIssue issue) => issue.isBlocking);

  /// Les problèmes qui empêchent la soumission.
  List<KdpIssue> get blockingIssues => List<KdpIssue>.unmodifiable(
    issues.where((KdpIssue issue) => issue.isBlocking),
  );
}

/// Le contrôle de soumission d'un livre.
///
/// Amazon refuse un dossier lorsque le texte est trop court, lorsque l'EPUB
/// ne porte pas de navigation ou lorsque le PDF d'impression n'a pas de
/// fond perdu. Le contrôle regarde les fichiers produits — et non la seule
/// intention de l'auteur — et rend la liste des problèmes : chaque
/// problème nomme ce qu'il faut corriger.
final class KdpSubmissionCheck {
  /// Crée un contrôle.
  const KdpSubmissionCheck();

  /// Vérifie le dossier préparé et rend le rapport.
  KdpSubmissionReport check({
    required KdpMetadata metadata,
    required ExportBook book,
    required Uint8List epubBytes,
    required Uint8List pdfBytes,
    required ExportOptions printOptions,
  }) {
    final PdfDocument pdf = PdfDocument.read(pdfBytes);
    final List<KdpIssue> issues = <KdpIssue>[
      ..._checkManuscript(book),
      ..._checkEpub(epubBytes),
      ..._checkPdf(pdf, printOptions),
      ..._checkMetadata(metadata),
    ];
    return KdpSubmissionReport(
      issues: List<KdpIssue>.unmodifiable(issues),
      wordCount: book.wordCount,
      pageCount: pdf.pageCount,
    );
  }

  /// Vérifie le manuscrit lui-même.
  List<KdpIssue> _checkManuscript(ExportBook book) {
    final List<KdpIssue> issues = <KdpIssue>[];
    if (book.chapters.isEmpty) {
      issues.add(
        const KdpIssue(
          code: 'manuscript_empty',
          field: 'project_id',
          message: "Le livre n'a aucun chapitre : il n'y a rien à publier.",
        ),
      );
      return issues;
    }
    final int words = book.wordCount;
    if (words < KdpRequirements.minWordCount) {
      issues.add(
        KdpIssue(
          code: 'text_too_short',
          field: 'manuscript',
          message:
              'Le texte compte $words mots. Amazon attend au moins '
              '${KdpRequirements.minWordCount} mots pour un livre '
              'électronique.',
        ),
      );
    }
    return issues;
  }

  /// Vérifie le paquet EPUB produit.
  List<KdpIssue> _checkEpub(Uint8List bytes) {
    final List<KdpIssue> issues = <KdpIssue>[];
    final EpubPackage? package = EpubPackage.read(bytes);
    if (package == null) {
      issues.add(
        const KdpIssue(
          code: 'epub_unreadable',
          field: 'epub',
          message:
              "Le fichier EPUB produit n'est pas un paquet lisible : Amazon "
              'refusera le dossier.',
        ),
      );
      return issues;
    }
    if (!package.hasMimeType) {
      issues.add(
        const KdpIssue(
          code: 'epub_no_mimetype',
          field: 'epub',
          message:
              "Le paquet EPUB ne porte pas l'entrée « mimetype » : Amazon "
              'refuse un EPUB qui ne la déclare pas.',
        ),
      );
    }
    if (package.navigationDocument == null) {
      issues.add(
        const KdpIssue(
          code: 'epub_no_navigation',
          field: 'epub',
          message:
              'Le fichier EPUB ne porte aucun document de navigation : '
              'Amazon refuse un EPUB sans table des matières.',
        ),
      );
      return issues;
    }
    if (!package.hasTableOfContents) {
      issues.add(
        const KdpIssue(
          code: 'epub_no_table_of_contents',
          field: 'epub',
          message:
              'Le document de navigation du EPUB ne déclare aucune table des '
              'matières.',
        ),
      );
    }
    if (!package.declaresNavigation) {
      issues.add(
        const KdpIssue(
          code: 'epub_navigation_not_declared',
          field: 'epub',
          message:
              'Le manifeste du EPUB ne déclare pas le document de navigation '
              'qu\'il contient.',
        ),
      );
    }
    if (package.spineItemCount == 0) {
      issues.add(
        const KdpIssue(
          code: 'epub_empty_spine',
          field: 'epub',
          message:
              'La liste de lecture du EPUB est vide : Amazon refuse un '
              'livre sans aucun chapitre.',
        ),
      );
    }
    return issues;
  }

  /// Vérifie le PDF d'impression produit.
  List<KdpIssue> _checkPdf(PdfDocument pdf, ExportOptions options) {
    final List<KdpIssue> issues = <KdpIssue>[];
    final double? width = pdf.mediaBoxWidth;
    final double? height = pdf.mediaBoxHeight;

    if (width == null || height == null) {
      issues.add(
        const KdpIssue(
          code: 'pdf_geometry_unreadable',
          field: 'pdf',
          message:
              "Le format de page du PDF d'impression n'a pas pu être lu : "
              'Amazon ne pourra pas vérifier le fond perdu.',
          severity: KdpIssueSeverity.warning,
        ),
      );
    } else {
      issues.addAll(_checkBleed(width, height, options));
    }

    issues.addAll(_checkMargins(options));

    if (pdf.pageCount < KdpRequirements.minPageCount) {
      issues.add(
        KdpIssue(
          code: 'pdf_too_few_pages',
          field: 'pdf',
          message:
              "Le PDF d'impression compte ${pdf.pageCount} pages. Amazon "
              'refuse un ouvrage imprimé de moins de '
              '${KdpRequirements.minPageCount} pages.',
        ),
      );
    }
    return issues;
  }

  /// Vérifie le fond perdu et le format final du PDF d'impression.
  List<KdpIssue> _checkBleed(
    double width,
    double height,
    ExportOptions options,
  ) {
    final List<KdpIssue> issues = <KdpIssue>[];
    final double bleedWidthMm =
        (width - options.trimWidthMm * PdfDocument.pointsPerMm) /
        2 /
        PdfDocument.pointsPerMm;
    final double bleedHeightMm =
        (height - options.trimHeightMm * PdfDocument.pointsPerMm) /
        2 /
        PdfDocument.pointsPerMm;
    final double bleedMm = bleedWidthMm < bleedHeightMm
        ? bleedWidthMm
        : bleedHeightMm;

    if (bleedMm < KdpRequirements.bleedMm - KdpRequirements.toleranceMm) {
      issues.add(
        KdpIssue(
          code: 'pdf_no_bleed',
          field: 'pdf',
          message:
              "Le PDF d'impression ne porte pas le fond perdu demandé par "
              'Amazon (${_formatMm(bleedMm)} mm au lieu de '
              '${_formatMm(KdpRequirements.bleedMm)} mm sur chaque bord).',
        ),
      );
    }

    final bool wrongWidth =
        (options.trimWidthMm - KdpRequirements.trimWidthMm).abs() >
        KdpRequirements.toleranceMm;
    final bool wrongHeight =
        (options.trimHeightMm - KdpRequirements.trimHeightMm).abs() >
        KdpRequirements.toleranceMm;
    if (wrongWidth || wrongHeight) {
      issues.add(
        KdpIssue(
          code: 'pdf_trim_size',
          field: 'pdf',
          message:
              'Le format imprimé fait ${_formatMm(options.trimWidthMm)} × '
              '${_formatMm(options.trimHeightMm)} mm. Amazon attend '
              '${_formatMm(KdpRequirements.trimWidthMm)} × '
              '${_formatMm(KdpRequirements.trimHeightMm)} mm (6 × 9 pouces).',
        ),
      );
    }
    return issues;
  }

  /// Vérifie les marges du PDF d'impression.
  List<KdpIssue> _checkMargins(ExportOptions options) {
    final List<KdpIssue> issues = <KdpIssue>[];
    final Map<String, double> margins = <String, double>{
      'margin_inside': options.marginInsideMm,
      'margin_outside': options.marginOutsideMm,
      'margin_top': options.marginTopMm,
      'margin_bottom': options.marginBottomMm,
    };
    for (final MapEntry<String, double> margin in margins.entries) {
      if (margin.value >=
          KdpRequirements.minMarginMm - KdpRequirements.toleranceMm) {
        continue;
      }
      issues.add(
        KdpIssue(
          code: 'pdf_margin_too_small',
          field: margin.key,
          message:
              'La marge « ${margin.key} » du PDF d\'impression fait '
              '${_formatMm(margin.value)} mm. Amazon exige au moins '
              '${_formatMm(KdpRequirements.minMarginMm)} mm.',
        ),
      );
    }
    return issues;
  }

  /// Vérifie les métadonnées que la fiche produit exige.
  List<KdpIssue> _checkMetadata(KdpMetadata metadata) {
    final List<KdpIssue> issues = <KdpIssue>[];
    if (metadata.isbn == null) {
      issues.add(
        const KdpIssue(
          code: 'isbn_missing',
          field: 'isbn',
          message:
              "L'édition imprimée exige un ISBN : ajoutez-le avant de déposer "
              'le dossier sur Amazon.',
        ),
      );
    }
    if (metadata.description.isEmpty) {
      issues.add(
        const KdpIssue(
          code: 'description_missing',
          field: 'description',
          message:
              "La fiche produit n'a pas de résumé : Amazon en affiche un "
              'par défaut, moins attractif.',
          severity: KdpIssueSeverity.warning,
        ),
      );
    }
    if (metadata.keywords.isEmpty) {
      issues.add(
        const KdpIssue(
          code: 'keywords_missing',
          field: 'keywords',
          message:
              'La fiche produit n\'a pas de mot-clé : le livre sera plus '
              'difficile à trouver.',
          severity: KdpIssueSeverity.warning,
        ),
      );
    }
    if (metadata.categories.isEmpty) {
      issues.add(
        const KdpIssue(
          code: 'categories_missing',
          field: 'categories',
          message:
              "La fiche produit n'a pas de catégorie : Amazon en choisira "
              'une à la place de l\'auteur.',
          severity: KdpIssueSeverity.warning,
        ),
      );
    }
    return issues;
  }

  /// Écrit une mesure en millimètres, à la française.
  static String _formatMm(double value) =>
      value.toStringAsFixed(1).replaceAll('.', ',');
}
