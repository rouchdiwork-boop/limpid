import 'pdf_fonts.dart';

/// Ligne de texte apres retour a la ligne.
class PdfTextLine {
  /// Cree une ligne de texte.
  const PdfTextLine({
    required this.text,
    required this.width,
    required this.wordCount,
  });

  /// Texte de la ligne.
  final String text;

  /// Largeur naturelle de la ligne, en points.
  final double width;

  /// Nombre de mots de la ligne.
  final int wordCount;
}

/// Mesure du texte et retour a la ligne.
///
/// Les largeurs sont mises en cache : la mesure est l'operation la plus
/// couteuse d'une pagination.
class PdfTextMeasure {
  /// Cree un mesureur.
  PdfTextMeasure(this.fonts);

  /// Polices utilisees.
  final PdfFontSet fonts;

  final Map<String, double> _widthCache = <String, double>{};

  /// Largeur du texte, en points.
  double widthOf(String text, PdfFontVariant font, double fontSize) {
    if (text.isEmpty) {
      return 0;
    }
    final key = '${font.hashCode}|$fontSize|$text';
    final cached = _widthCache[key];
    if (cached != null) {
      return cached;
    }
    final safe = sanitize(text, font);
    var width = 0.0;
    try {
      width = font.metric.stringMetrics(safe).width * fontSize;
    } on Object {
      width = safe.length * fontSize * 0.5;
    }
    _widthCache[key] = width;
    return width;
  }

  /// Remplace les caracteres non rendus par une police de substitution.
  ///
  /// Les polices de substitution (Times, Helvetica, Courier) couvrent le
  /// jeu Latin-1 : les caracteres typographiques sont translitteres, les
  /// autres sont remplaces par un point d'interrogation.
  String sanitize(String text, PdfFontVariant font) {
    if (!font.isFallback) {
      return text;
    }
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final transliterated = _transliterations[rune];
      if (transliterated != null) {
        buffer.write(transliterated);
        continue;
      }
      if (rune < 0x20 || rune > 0xFF || !font.supports(rune)) {
        buffer.write('?');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Translitterations des caracteres typographiques hors Latin-1.
  static const Map<int, String> _transliterations = <int, String>{
    0x2018: "'",
    0x2019: "'",
    0x201A: "'",
    0x201B: "'",
    0x201C: '"',
    0x201D: '"',
    0x201E: '"',
    0x2013: '-',
    0x2014: '-',
    0x2015: '-',
    0x2026: '.',
    0x00A0: ' ',
    0x202F: ' ',
  };

  /// Decoupe un texte en lignes tenant dans [maxWidth].
  ///
  /// Les blancs multiples sont normalises, les retours a la ligne explicites
  /// sont conserves.
  List<PdfTextLine> wrap(
    String text,
    PdfFontVariant font,
    double fontSize,
    double maxWidth, {
    bool hyphenate = false,
  }) {
    final lines = <PdfTextLine>[];
    if (maxWidth <= 0) {
      return lines;
    }
    final spaceWidth = widthOf(' ', font, fontSize);

    for (final paragraph in text.split('\n')) {
      final words = paragraph
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      if (words.isEmpty) {
        lines.add(const PdfTextLine(text: '', width: 0, wordCount: 0));
        continue;
      }

      var current = <String>[];
      var currentWidth = 0.0;

      for (final word in words) {
        final wordWidth = widthOf(word, font, fontSize);
        final separator = current.isEmpty ? 0.0 : spaceWidth;
        final candidate = currentWidth + separator + wordWidth;

        if (candidate <= maxWidth) {
          current.add(word);
          currentWidth = candidate;
          continue;
        }

        if (current.isNotEmpty) {
          lines.add(
            PdfTextLine(
              text: current.join(' '),
              width: currentWidth,
              wordCount: current.length,
            ),
          );
          current = <String>[];
          currentWidth = 0;
        }

        if (wordWidth <= maxWidth) {
          current = <String>[word];
          currentWidth = wordWidth;
          continue;
        }

        final pieces = _hardBreak(word, font, fontSize, maxWidth, hyphenate);
        for (var index = 0; index < pieces.length - 1; index++) {
          lines.add(
            PdfTextLine(
              text: pieces[index],
              width: widthOf(pieces[index], font, fontSize),
              wordCount: 1,
            ),
          );
        }
        final last = pieces.last;
        current = <String>[last];
        currentWidth = widthOf(last, font, fontSize);
      }

      lines.add(
        PdfTextLine(
          text: current.join(' '),
          width: currentWidth,
          wordCount: current.length,
        ),
      );
    }
    return lines;
  }

  List<String> _hardBreak(
    String word,
    PdfFontVariant font,
    double fontSize,
    double maxWidth,
    bool hyphenate,
  ) {
    final pieces = <String>[];
    var current = StringBuffer();
    for (final rune in word.runes) {
      final char = String.fromCharCode(rune);
      final candidate = current.toString() + char;
      if (widthOf(candidate, font, fontSize) > maxWidth && current.isNotEmpty) {
        pieces.add(hyphenate ? '$current-' : current.toString());
        current = StringBuffer(char);
      } else {
        current.write(char);
      }
    }
    pieces.add(current.toString());
    return pieces;
  }
}
