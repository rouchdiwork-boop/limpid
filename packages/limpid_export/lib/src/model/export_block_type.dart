/// Nature d'un bloc de contenu dans le modele intermediaire d'export.
enum ExportBlockType {
  /// Paragraphe de corps de texte.
  paragraph,

  /// Titre de niveau 1 (titre de chapitre).
  heading1,

  /// Titre de niveau 2.
  heading2,

  /// Titre de niveau 3.
  heading3,

  /// Element de liste.
  listItem,

  /// Citation en exergue.
  quote,

  /// Bloc de code ou de verbatim.
  code,

  /// Illustration.
  image,

  /// Saut de page explicite.
  pageBreak,

  /// Note de bas de page autonome.
  footnote;

  /// Vrai si ce type de bloc produit une ligne de texte.
  bool get isTextual =>
      this != ExportBlockType.image &&
      this != ExportBlockType.pageBreak &&
      this != ExportBlockType.footnote;

  /// Vrai si ce type de bloc est un titre.
  bool get isHeading =>
      this == ExportBlockType.heading1 ||
      this == ExportBlockType.heading2 ||
      this == ExportBlockType.heading3;
}
