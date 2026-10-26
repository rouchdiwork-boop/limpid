/// Echappement du texte pour la syntaxe Markdown.
///
/// Le texte d'un livre peut contenir n'importe quels caracteres ; les
/// marqueurs Markdown doivent etre neutralises pour que le rendu reste
/// fidele a l'original.
class MarkdownEscaper {
  const MarkdownEscaper._();

  static const String _alwaysEscaped = r'\`*_[]<>';

  /// Echappe une valeur en ligne.
  static String inline(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (_alwaysEscaped.contains(char)) {
        buffer.write('\\$char');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Echappe un bloc de texte, ligne par ligne.
  ///
  /// Les marqueurs de debut de ligne (`#`, `>`, `-`, `*`, `+`, chiffres
  /// suivis d'un point) sont neutralises.
  static String block(String text) {
    return text.split('\n').map(inline).map(_escapeLineStart).join('\n');
  }

  static String _escapeLineStart(String line) {
    if (line.isEmpty) {
      return line;
    }
    const markers = '#>-*+';
    if (markers.contains(line[0])) {
      return '\\${line[0]}${line.substring(1)}';
    }
    final dotIndex = line.indexOf('. ');
    if (dotIndex > 0) {
      final prefix = line.substring(0, dotIndex);
      final isOrdered = RegExp(r'^\d+$').hasMatch(prefix);
      if (isOrdered) {
        return '\\$prefix.${line.substring(dotIndex + 1)}';
      }
    }
    return line;
  }
}
