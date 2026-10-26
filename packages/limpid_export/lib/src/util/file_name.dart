/// Utilitaires de nommage de fichiers.
///
/// Les noms produits ne contiennent que des caracteres ASCII sûrs, afin
/// d'etre utilisables sur tous les systemes de fichiers et dans les archives.
class FileNames {
  const FileNames._();

  /// Transforme un titre en nom de fichier stable et lisible.
  ///
  /// Les accents sont translitteres, la ponctuation est supprimee et les
  /// espaces deviennent des tirets. Le resultat n'est jamais vide.
  static String slug(String title, {String fallback = 'livre'}) {
    final transliterated = _transliterate(title);
    final buffer = StringBuffer();
    var lastWasDash = true;
    for (final rune in transliterated.runes) {
      final char = String.fromCharCode(rune);
      final isLetter = _isAsciiLetter(char);
      final isDigit = _isAsciiDigit(char);
      if (isLetter || isDigit) {
        buffer.write(char.toLowerCase());
        lastWasDash = false;
      } else if (!lastWasDash) {
        buffer.write('-');
        lastWasDash = true;
      }
    }
    final slug = buffer.toString().replaceAll(RegExp(r'-+$'), '');
    if (slug.isEmpty) {
      return fallback;
    }
    return slug.length <= 80
        ? slug
        : slug.substring(0, 80).replaceAll(RegExp(r'-+$'), '');
  }

  /// Construit un nom de fichier a partir d'un titre et d'une extension.
  static String forBook(String title, String extension) =>
      '${slug(title)}.${extension.toLowerCase()}';

  /// Numero de chapitre sur deux chiffres, pour les noms de fichiers.
  static String chapterNumber(int index) =>
      (index + 1).toString().padLeft(2, '0');

  static bool _isAsciiLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static bool _isAsciiDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static const Map<String, String> _transliterations = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ø': 'o',
    'œ': 'oe',
    'ß': 'ss',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    '«': ' ',
    '»': ' ',
    '’': ' ',
    '‘': ' ',
    '–': '-',
    '—': '-',
  };

  static String _transliterate(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_transliterations[char] ?? char);
    }
    return buffer.toString();
  }
}
