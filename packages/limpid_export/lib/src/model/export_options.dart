/// Format de page utilisable pour les sorties paginees (PDF).
enum ExportPageSize {
  /// A4 (210 x 297 mm).
  a4,

  /// A5 (148 x 210 mm).
  a5,

  /// B5 (176 x 250 mm).
  b5,

  /// Letter (215,9 x 279,4 mm).
  letter,

  /// Format libre, defini par [ExportOptions.customWidthMm].
  custom,
}

/// Mode de generation PDF.
enum ExportPdfMode {
  /// Pagination automatique, lisible a l'ecran.
  reflowable,

  /// Format impose pour l'impression (fond perdu, marges miroir).
  printReady,
}

/// Options de rendu d'un export.
///
/// Toutes les distances sont exprimees en millimetres, toutes les tailles de
/// police en points. Les valeurs par defaut correspondent a un livre de
/// lecture : A5, 11 pt, interligne 1,5.
class ExportOptions {
  /// Cree un jeu d'options.
  const ExportOptions({
    this.fontFamily = defaultFontFamily,
    this.fontSize = 11,
    this.lineHeight = 1.5,
    this.marginTopMm = 20,
    this.marginBottomMm = 20,
    this.marginInsideMm = 20,
    this.marginOutsideMm = 15,
    this.pageSize = ExportPageSize.a5,
    this.customWidthMm = 148,
    this.customHeightMm = 210,
    this.trimWidthMm = 152.4,
    this.trimHeightMm = 228.6,
    this.bleedMm = 3,
    this.pdfMode = ExportPdfMode.reflowable,
    this.includeTitlePage = true,
    this.includeTableOfContents = true,
    this.includePageNumbers = true,
    this.includeRunningHeader = true,
    this.includeCoverImage = true,
    this.hyphenation = false,
    this.justifyText = false,
    this.imageDpi = 300,
    this.exportDate,
  });

  /// Police de corps de texte par defaut (cf. D-13 : Literata pour le
  /// manuscrit).
  static const String defaultFontFamily = 'Literata';

  /// Preset de lecture : A5, 11 pt, interligne 1,5.
  static const ExportOptions reflowable = ExportOptions();

  /// Preset d'impression : 6 x 9 pouces, fond perdu 3 mm, marges miroir.
  static const ExportOptions printReady = ExportOptions(
    fontSize: 10.5,
    lineHeight: 1.4,
    marginTopMm: 15,
    marginBottomMm: 18,
    pageSize: ExportPageSize.custom,
    customWidthMm: 152.4,
    customHeightMm: 228.6,
    pdfMode: ExportPdfMode.printReady,
    includeRunningHeader: false,
    justifyText: true,
  );

  /// Famille de police utilisee pour le corps de texte.
  final String fontFamily;

  /// Taille du corps de texte, en points.
  final double fontSize;

  /// Interligne, en multiple de la taille de police.
  final double lineHeight;

  /// Marge haute, en millimetres.
  final double marginTopMm;

  /// Marge basse, en millimetres.
  final double marginBottomMm;

  /// Marge interieure (reliure), en millimetres.
  final double marginInsideMm;

  /// Marge exterieure, en millimetres.
  final double marginOutsideMm;

  /// Format de page.
  final ExportPageSize pageSize;

  /// Largeur du format libre, en millimetres.
  final double customWidthMm;

  /// Hauteur du format libre, en millimetres.
  final double customHeightMm;

  /// Format final du livre imprime, en millimetres (mode print-ready).
  final double trimWidthMm;

  /// Format final du livre imprime, en millimetres (mode print-ready).
  final double trimHeightMm;

  /// Fond perdu, en millimetres (0 = aucun fond perdu).
  final double bleedMm;

  /// Mode de generation PDF.
  final ExportPdfMode pdfMode;

  /// Insere une page de titre.
  final bool includeTitlePage;

  /// Insere une table des matieres.
  final bool includeTableOfContents;

  /// Affiche les numeros de page.
  final bool includePageNumbers;

  /// Affiche un titre courant en tete de page.
  final bool includeRunningHeader;

  /// Embarque la couverture dans le fichier produit.
  final bool includeCoverImage;

  /// Active la coupe des mots en fin de ligne.
  final bool hyphenation;

  /// Justifie le corps de texte.
  final bool justifyText;

  /// Resolution cible des illustrations, en points par pouce.
  final int imageDpi;

  /// Date d'export, utilisee pour rendre les fichiers reproductibles.
  ///
  /// A defaut de date fournie, la date de publication du livre est utilisee ;
  /// a defaut, une date fixe est employees afin que deux exports identiques
  /// produisent les memes octets.
  final DateTime? exportDate;

  /// Copie immuable des options.
  ExportOptions copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? marginTopMm,
    double? marginBottomMm,
    double? marginInsideMm,
    double? marginOutsideMm,
    ExportPageSize? pageSize,
    double? customWidthMm,
    double? customHeightMm,
    double? trimWidthMm,
    double? trimHeightMm,
    double? bleedMm,
    ExportPdfMode? pdfMode,
    bool? includeTitlePage,
    bool? includeTableOfContents,
    bool? includePageNumbers,
    bool? includeRunningHeader,
    bool? includeCoverImage,
    bool? hyphenation,
    bool? justifyText,
    int? imageDpi,
    DateTime? exportDate,
  }) {
    return ExportOptions(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      marginTopMm: marginTopMm ?? this.marginTopMm,
      marginBottomMm: marginBottomMm ?? this.marginBottomMm,
      marginInsideMm: marginInsideMm ?? this.marginInsideMm,
      marginOutsideMm: marginOutsideMm ?? this.marginOutsideMm,
      pageSize: pageSize ?? this.pageSize,
      customWidthMm: customWidthMm ?? this.customWidthMm,
      customHeightMm: customHeightMm ?? this.customHeightMm,
      trimWidthMm: trimWidthMm ?? this.trimWidthMm,
      trimHeightMm: trimHeightMm ?? this.trimHeightMm,
      bleedMm: bleedMm ?? this.bleedMm,
      pdfMode: pdfMode ?? this.pdfMode,
      includeTitlePage: includeTitlePage ?? this.includeTitlePage,
      includeTableOfContents:
          includeTableOfContents ?? this.includeTableOfContents,
      includePageNumbers: includePageNumbers ?? this.includePageNumbers,
      includeRunningHeader: includeRunningHeader ?? this.includeRunningHeader,
      includeCoverImage: includeCoverImage ?? this.includeCoverImage,
      hyphenation: hyphenation ?? this.hyphenation,
      justifyText: justifyText ?? this.justifyText,
      imageDpi: imageDpi ?? this.imageDpi,
      exportDate: exportDate ?? this.exportDate,
    );
  }

  /// Largeur de page hors marges, en millimetres.
  double get contentWidthMm => pageWidthMm - marginInsideMm - marginOutsideMm;

  /// Hauteur de page hors marges, en millimetres.
  double get contentHeightMm => pageHeightMm - marginTopMm - marginBottomMm;

  /// Largeur de page, en millimetres.
  double get pageWidthMm => switch (pageSize) {
    ExportPageSize.a4 => 210,
    ExportPageSize.a5 => 148,
    ExportPageSize.b5 => 176,
    ExportPageSize.letter => 215.9,
    ExportPageSize.custom => customWidthMm,
  };

  /// Hauteur de page, en millimetres.
  double get pageHeightMm => switch (pageSize) {
    ExportPageSize.a4 => 297,
    ExportPageSize.a5 => 210,
    ExportPageSize.b5 => 250,
    ExportPageSize.letter => 279.4,
    ExportPageSize.custom => customHeightMm,
  };
}
