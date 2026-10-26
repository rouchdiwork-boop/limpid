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

/// Une famille de police du catalogue, avec le prefixe de ses fichiers.
class EmbeddedFontFamily {
  /// Cree une famille de police.
  const EmbeddedFontFamily({required this.name, required this.fileStem});

  /// Nom de la famille, tel qu'il est declare dans le `pubspec`.
  final String name;

  /// Prefixe des noms de fichiers de la famille.
  final String fileStem;

  /// Chemin de l'asset d'une variante de cette famille.
  String assetPathFor(FontVariant variant) {
    return '${LimpidFonts.assetDirectory}/$fileStem-${_variantSuffix(variant)}.ttf';
  }

  /// Les quatre references de police de cette famille.
  List<EmbeddedFont> assets() {
    return FontVariant.values
        .map(
          (variant) => EmbeddedFont(
            family: name,
            variant: variant,
            assetPath: assetPathFor(variant),
          ),
        )
        .toList(growable: false);
  }

  @override
  String toString() => 'EmbeddedFontFamily($name, $fileStem)';
}

/// Suffixe de fichier d'une variante de police.
String _variantSuffix(FontVariant variant) {
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

/// Catalogue des faces embarquees prevues par le projet (cf. D-13).
///
/// Les fichiers sont livres dans `assets/fonts/`, avec leur licence OFL.
/// Cote serveur, le moteur d'export les lit sur le disque ; cote
/// application, Flutter les sert depuis le bundle. Aucune police n'est
/// telechargee a l'execution.
class LimpidFonts {
  const LimpidFonts._();

  /// Prefixe des chemins d'assets des polices.
  static const String assetDirectory = 'assets/fonts';

  /// Les quatre familles du projet, dans l'ordre de preference.
  static const List<String> families = <String>[
    'Literata',
    'Fraunces',
    'Instrument Sans',
    'IBM Plex Mono',
  ];

  /// Les familles du projet, avec le prefixe de leurs fichiers.
  ///
  /// Le prefixe de fichier ne reprend pas toujours le nom de la famille :
  /// `Instrument Sans` est livre sous `InstrumentSans-*.ttf` et
  /// `IBM Plex Mono` sous `IBMPlexMono-*.ttf`.
  static const List<EmbeddedFontFamily> catalogue = <EmbeddedFontFamily>[
    EmbeddedFontFamily(name: 'Literata', fileStem: 'Literata'),
    EmbeddedFontFamily(name: 'Fraunces', fileStem: 'Fraunces'),
    EmbeddedFontFamily(name: 'Instrument Sans', fileStem: 'InstrumentSans'),
    EmbeddedFontFamily(name: 'IBM Plex Mono', fileStem: 'IBMPlexMono'),
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

  /// La famille du catalogue qui porte ce nom, ou `null`.
  static EmbeddedFontFamily? familyNamed(String name) {
    for (final family in catalogue) {
      if (family.name == name) {
        return family;
      }
    }
    return null;
  }

  /// Reference vers le fichier de police d'une famille et d'une variante.
  ///
  /// Une famille inconnue du catalogue est traduite en un prefixe de
  /// fichier derive de son nom : le moteur tente alors de la charger, puis
  /// signale son absence.
  static EmbeddedFont assetFor(String family, FontVariant variant) {
    final descriptor =
        familyNamed(family) ??
        EmbeddedFontFamily(name: family, fileStem: family.replaceAll(' ', ''));
    return EmbeddedFont(
      family: family,
      variant: variant,
      assetPath: descriptor.assetPathFor(variant),
    );
  }

  /// Toutes les references de police d'une famille.
  static List<EmbeddedFont> assetsFor(String family) {
    return FontVariant.values
        .map((variant) => assetFor(family, variant))
        .toList(growable: false);
  }
}
