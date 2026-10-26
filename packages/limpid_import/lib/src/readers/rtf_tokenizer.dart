/// Un jeton du langage RTF.
sealed class RtfToken {
  /// Cree un jeton.
  const RtfToken();
}

/// L'ouverture d'un groupe.
final class RtfGroupStart extends RtfToken {
  /// Cree un jeton d'ouverture de groupe.
  const RtfGroupStart();
}

/// La fermeture d'un groupe.
final class RtfGroupEnd extends RtfToken {
  /// Cree un jeton de fermeture de groupe.
  const RtfGroupEnd();
}

/// Un mot de controle.
///
/// Le parametre est `null` quand le mot de controle n'en porte pas.
final class RtfControlWord extends RtfToken {
  /// Cree un jeton de mot de controle.
  const RtfControlWord(this.name, [this.parameter]);

  /// Le nom du mot de controle, sans la barre oblique inverse.
  final String name;

  /// Le parametre du mot de controle, `null` quand il n'y en a pas.
  final int? parameter;
}

/// Un caractere ecrit en hexadecimal (`\'e9`).
final class RtfHexEscape extends RtfToken {
  /// Cree un jeton d'echappement hexadecimal.
  const RtfHexEscape(this.value);

  /// La valeur du caractere.
  final int value;
}

/// Du texte litteral.
final class RtfText extends RtfToken {
  /// Cree un jeton de texte.
  const RtfText(this.text);

  /// Le texte porte par le jeton.
  final String text;
}

/// Decoupe un document RTF en jetons.
///
/// Le decoupage est purement lexical : il ne dit rien du sens des mots de
/// controle. C'est le lecteur qui donne leur sens.
List<RtfToken> tokenizeRtf(String source) {
  final List<RtfToken> tokens = <RtfToken>[];
  var index = 0;
  while (index < source.length) {
    final String char = source[index];

    if (char == '{') {
      tokens.add(const RtfGroupStart());
      index++;
      continue;
    }
    if (char == '}') {
      tokens.add(const RtfGroupEnd());
      index++;
      continue;
    }
    if (char == '\\') {
      index = _readControlWord(source, index + 1, tokens);
      continue;
    }

    final int start = index;
    while (index < source.length) {
      final String current = source[index];
      if (current == '{' || current == '}' || current == '\\') break;
      index++;
    }
    if (index == start) {
      index++;
      continue;
    }
    tokens.add(RtfText(source.substring(start, index)));
  }
  return tokens;
}

int _readControlWord(String source, int index, List<RtfToken> tokens) {
  if (index >= source.length) return index;
  final String next = source[index];

  if (next == "'") {
    if (index + 2 < source.length) {
      final int? value = int.tryParse(
        source.substring(index + 1, index + 3),
        radix: 16,
      );
      if (value != null) {
        tokens.add(RtfHexEscape(value));
        return index + 3;
      }
    }
    return index + 1;
  }

  if (!_isLetter(next)) {
    // Un symbole de controle : `\*`, `\\`, `\{`, `\}`.
    // La barre oblique inverse suivie d'un retour a la ligne est un
    // `\par`, comme le veut la specification.
    if (next == '\n' || next == '\r') {
      tokens.add(const RtfControlWord('par'));
      return index + 1;
    }
    tokens.add(RtfControlWord(next));
    return index + 1;
  }

  final int start = index;
  while (index < source.length && _isLetter(source[index])) {
    index++;
  }
  final String name = source.substring(start, index);

  int? parameter;
  if (index < source.length &&
      (source[index] == '-' || _isDigit(source[index]))) {
    final int parameterStart = index;
    if (source[index] == '-') index++;
    while (index < source.length && _isDigit(source[index])) {
      index++;
    }
    parameter = int.tryParse(source.substring(parameterStart, index));
  }

  // L'espace qui suit un mot de controle est un separateur : il ne fait
  // pas partie du texte.
  if (index < source.length && source[index] == ' ') index++;

  tokens.add(RtfControlWord(name, parameter));
  return index;
}

bool _isLetter(String char) {
  final int code = char.codeUnitAt(0);
  return code >= 0x41 && code <= 0x5A || code >= 0x61 && code <= 0x7A;
}

bool _isDigit(String char) {
  final int code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}
