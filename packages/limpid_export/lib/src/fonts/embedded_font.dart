/// Variante d'une famille de police.
enum FontVariant {
  /// Poids normal, style normal.
  regular,

  /// Gras.
  bold,

  /// Italique.
  italic,

  /// Gras italique.
  boldItalic,
}

/// Fichier de police embarque dans l'application.
///
/// Les polices ne sont jamais telechargees : elles sont livrees en assets
/// (licence OFL) et injectees dans le moteur d'export par l'application.
class EmbeddedFont {
  /// Cree une reference vers un fichier de police embarque.
  const EmbeddedFont({
    required this.family,
    required this.variant,
    required this.assetPath,
  });

  /// Nom de la famille (par exemple `Literata`).
  final String family;

  /// Variante de la famille.
  final FontVariant variant;

  /// Chemin de l'asset dans le bundle de l'application.
  final String assetPath;

  @override
  String toString() => 'EmbeddedFont($family, ${variant.name}, $assetPath)';
}

/// Catalogue des faces embarquees prevues par le projet (cf. D-13).
///
/// Les fichiers eux-memes ne sont pas versionnes dans ce depot : ils sont
/// ajoutes par l'application (ou par le pipeline de build) dans le dossier
/// `assets/fonts/`. Voir `assets/fonts/README.md`.
class LimpidFonts {
  const LimpidFonts._();

  /// Prefixe des chemins d'assets des polices.
  static const String assetDirectory = 'assets/fonts';

  /// Familles disponibles, dans l'ordre de preference de substitution.
  static const List<String> families = <String>[
    'Literata',
    'Fraunces',
    'Instrument Sans',
    'IBM Plex Mono',
  ];

  /// Familles de substitution disponibles dans le moteur PDF.
  ///
  /// Ces familles sont livrees avec le moteur PDF lui-meme : elles ne
  /// dependent d'aucun asset et servent de repli quand une police embarquee
  /// est absente.
  static const Map<String, String> substitutions = <String, String>{
    'Literata': 'Times',
    'Fraunces': 'Times',
    'Instrument Sans': 'Helvetica',
    'IBM Plex Mono': 'Courier',
  };

  /// Reference vers le fichier de police d'une famille et d'une variante.
  static EmbeddedFont assetFor(String family, FontVariant variant) {
    return EmbeddedFont(
      family: family,
      variant: variant,
      assetPath: '$assetDirectory/$family-${_suffix(variant)}.ttf',
    );
  }

  /// Toutes les references de police d'une famille.
  static List<EmbeddedFont> assetsFor(String family) {
    return FontVariant.values
        .map((variant) => assetFor(family, variant))
        .toList(growable: false);
  }

  static String _suffix(FontVariant variant) {
    switch (variant) {
      case FontVariant.regular:
        return 'Regular';
      case FontVariant.bold:
        return 'Bold';
      case FontVariant.italic:
        return 'Italic';
      case FontVariant.boldItalic:
        return 'BoldItalic';
    }
  }
}
