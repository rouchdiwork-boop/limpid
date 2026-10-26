/// Approximate metrics of the texts printed on a cover.
///
/// The export package has no font engine: the widths are estimated from a
/// table of character factors. The estimation is accurate enough to lay a
/// title out on a few lines, and it is deterministic, which the cover
/// requires.
class CoverTextMetrics {
  const CoverTextMetrics._();

  static const String _narrow = 'ijltfrI.,;:!?';
  static const String _wide = 'mwMW@';

  /// The width of [text] set at [fontSize].
  ///
  /// [letterSpacing] is added after every character.
  static double widthOf(
    String text, {
    required double fontSize,
    double letterSpacing = 0,
  }) {
    var units = 0.0;
    for (final rune in text.runes) {
      units += _factorOf(String.fromCharCode(rune));
    }
    return units * fontSize + letterSpacing * text.length;
  }

  /// Wraps [text] on lines of at most [maxWidth].
  ///
  /// A word wider than [maxWidth] keeps its own line: the cover never cuts
  /// a word in the middle.
  static List<String> wrap(
    String text, {
    required double fontSize,
    required double maxWidth,
    double letterSpacing = 0,
  }) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return const <String>[];
    }

    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      final fits =
          widthOf(
            candidate,
            fontSize: fontSize,
            letterSpacing: letterSpacing,
          ) <=
          maxWidth;
      if (fits || current.isEmpty) {
        current = candidate;
        continue;
      }
      lines.add(current);
      current = word;
    }
    if (current.isNotEmpty) {
      lines.add(current);
    }
    return List<String>.unmodifiable(lines);
  }

  /// Wraps [text] on at most [maxLines] lines.
  ///
  /// The font shrinks until the text fits, down to [minFontSize]; the last
  /// line is then closed by an ellipsis.
  static List<String> fit(
    String text, {
    required double fontSize,
    required double minFontSize,
    required double maxWidth,
    required int maxLines,
    double letterSpacing = 0,
    double shrinkStep = 0.92,
  }) {
    var size = fontSize;
    var lines = wrap(
      text,
      fontSize: size,
      maxWidth: maxWidth,
      letterSpacing: letterSpacing,
    );
    while (lines.length > maxLines && size > minFontSize) {
      final shrunk = size * shrinkStep;
      size = shrunk < minFontSize ? minFontSize : shrunk;
      lines = wrap(
        text,
        fontSize: size,
        maxWidth: maxWidth,
        letterSpacing: letterSpacing,
      );
    }
    if (lines.length <= maxLines) {
      return lines;
    }
    final kept = lines.sublist(0, maxLines);
    return List<String>.unmodifiable(<String>[
      ...kept.sublist(0, maxLines - 1),
      '${kept[maxLines - 1]}$_ellipsis',
    ]);
  }

  /// Cuts [text] to [maxWidth] and closes it with an ellipsis.
  static String truncate(
    String text, {
    required double fontSize,
    required double maxWidth,
    double letterSpacing = 0,
  }) {
    if (text.isEmpty) {
      return '';
    }
    final fits =
        widthOf(text, fontSize: fontSize, letterSpacing: letterSpacing) <=
        maxWidth;
    if (fits) {
      return text;
    }

    var kept = '';
    for (final rune in text.runes) {
      final candidate = '$kept${String.fromCharCode(rune)}';
      final candidateWidth = widthOf(
        '$candidate$_ellipsis',
        fontSize: fontSize,
        letterSpacing: letterSpacing,
      );
      if (candidateWidth > maxWidth) {
        break;
      }
      kept = candidate;
    }
    return '$kept$_ellipsis';
  }

  /// The width of a character, against the size of the font.
  ///
  /// The factors are deliberately generous: the estimation must never
  /// under-estimate the width of a text, or the title would overflow the
  /// face of the cover.
  static double _factorOf(String char) {
    if (char == ' ') {
      return 0.26;
    }
    if (_narrow.contains(char)) {
      return 0.32;
    }
    if (_wide.contains(char)) {
      return 0.88;
    }
    if (char == '—' || char == '–') {
      return 1;
    }
    final code = char.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      return 0.72;
    }
    if (code >= 48 && code <= 57) {
      return 0.56;
    }
    return 0.54;
  }

  /// The mark closing a text that could not be printed entirely.
  static const String _ellipsis = '…';
}
