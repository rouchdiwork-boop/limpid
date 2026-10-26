/// Les formats de manuscrit que le moteur d'import sait lire.
///
/// Le format est reconnu par l'extension du fichier ou par son type MIME ;
/// le contenu n'est jamais deviné au hasard, sauf quand le nom ne porte
/// aucune information (voir `ImportFormatDetector`).
enum ImportFormat {
  /// Un document Word : un paquet OOXML dont le corps est
  /// `word/document.xml`.
  docx(
    extension: 'docx',
    mimeTypes: <String>{
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    },
  ),

  /// Un document OpenDocument Text : un paquet ODF dont le corps est
  /// `content.xml`.
  odt(
    extension: 'odt',
    mimeTypes: <String>{'application/vnd.oasis.opendocument.text'},
  ),

  /// Un livre electronique EPUB : un paquet dont le contenu est decrit par
  /// un document OPF et une spine.
  epub(extension: 'epub', mimeTypes: <String>{'application/epub+zip'}),

  /// Un document RTF (Rich Text Format).
  rtf(extension: 'rtf', mimeTypes: <String>{'application/rtf', 'text/rtf'}),

  /// Un document Markdown.
  markdown(
    extension: 'md',
    mimeTypes: <String>{
      'text/markdown',
      'text/x-markdown',
      'application/markdown',
    },
  ),

  /// Un fichier texte brut.
  txt(extension: 'txt', mimeTypes: <String>{'text/plain'});

  const ImportFormat({required this.extension, required this.mimeTypes});

  /// L'extension canonique du format, sans le point.
  final String extension;

  /// Les types MIME qui designent ce format.
  final Set<String> mimeTypes;

  /// Le nom du format dans le vocabulaire stable de l'API.
  ///
  /// C'est le nom du paquet dans le nom de l'extension : `markdown` et
  /// `txt`, jamais `md` et `text`.
  String get label => name;

  /// Toutes les extensions qui designent ce format.
  ///
  /// Markdown a plusieurs extensions usuelles ; les autres formats n'en ont
  /// qu'une.
  Set<String> get extensions => switch (this) {
    ImportFormat.markdown => const <String>{'md', 'markdown', 'mdown'},
    _ => <String>{extension},
  };

  /// Le format designe par l'extension [extension], `null` quand elle est
  /// inconnue.
  static ImportFormat? fromExtension(String extension) {
    final String needle = extension.toLowerCase();
    for (final ImportFormat format in ImportFormat.values) {
      if (format.extensions.contains(needle)) return format;
    }
    return null;
  }

  /// Le format designe par le type MIME [mimeType], `null` quand il est
  /// inconnu.
  ///
  /// Les parametres du type MIME (`; charset=utf-8`) sont ignores.
  static ImportFormat? fromMimeType(String mimeType) {
    final String needle = _withoutParameters(mimeType);
    for (final ImportFormat format in ImportFormat.values) {
      if (format.mimeTypes.contains(needle)) return format;
    }
    return null;
  }

  static String _withoutParameters(String mimeType) {
    final int separator = mimeType.indexOf(';');
    final String head = separator < 0
        ? mimeType
        : mimeType.substring(0, separator);
    return head.trim().toLowerCase();
  }
}
