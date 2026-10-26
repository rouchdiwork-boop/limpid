/// Splits a SQL script into the statements it holds.
///
/// The `sqlite3` package executes one statement per call, so a migration file
/// has to be cut before it can be applied. The splitter knows the places
/// where a semicolon does **not** end a statement: inside a string literal,
/// inside a quoted identifier and inside a comment.
///
/// The statements are returned without their trailing semicolon, which
/// `sqlite3` refuses on a prepared statement.
final class SqlStatementSplitter {
  /// Creates a splitter.
  const SqlStatementSplitter();

  /// Splits [script] into its statements.
  ///
  /// The comments are kept, so the migration stays readable in the logs of
  /// the engine, but a statement made of comments only is dropped.
  List<String> split(String script) {
    final List<String> statements = <String>[];
    final StringBuffer current = StringBuffer();
    bool hasCode = false;
    int index = 0;
    final int length = script.length;

    while (index < length) {
      final String character = script[index];
      final bool startsComment =
          character == '-' && index + 1 < length && script[index + 1] == '-';
      final bool startsBlockComment =
          character == '/' && index + 1 < length && script[index + 1] == '*';

      if (startsComment) {
        final int end = _endOfLineComment(script, index);
        current.write(script.substring(index, end));
        index = end;
        continue;
      }

      if (startsBlockComment) {
        final int end = _endOfBlockComment(script, index);
        current.write(script.substring(index, end));
        index = end;
        continue;
      }

      if (character == "'" || character == '"' || character == '`') {
        final int end = _endOfQuoted(script, index, character);
        current.write(script.substring(index, end));
        hasCode = true;
        index = end;
        continue;
      }

      if (character == '[') {
        final int end = _endOfBracketedIdentifier(script, index);
        current.write(script.substring(index, end));
        hasCode = true;
        index = end;
        continue;
      }

      if (character == ';') {
        _emit(current, statements, hasCode);
        hasCode = false;
        index++;
        continue;
      }

      if (character.trim().isNotEmpty) hasCode = true;
      current.write(character);
      index++;
    }

    _emit(current, statements, hasCode);
    return List<String>.unmodifiable(statements);
  }

  static void _emit(
    StringBuffer current,
    List<String> statements,
    bool hasCode,
  ) {
    if (!hasCode) {
      current.clear();
      return;
    }
    statements.add(current.toString().trim());
    current.clear();
  }

  static int _endOfLineComment(String script, int start) {
    final int newline = script.indexOf('\n', start);
    return newline == -1 ? script.length : newline;
  }

  static int _endOfBlockComment(String script, int start) {
    final int end = script.indexOf('*/', start + 2);
    return end == -1 ? script.length : end + 2;
  }

  static int _endOfQuoted(String script, int start, String quote) {
    int index = start + 1;
    while (index < script.length) {
      if (script[index] != quote) {
        index++;
        continue;
      }
      if (index + 1 < script.length && script[index + 1] == quote) {
        index += 2;
        continue;
      }
      return index + 1;
    }
    return script.length;
  }

  static int _endOfBracketedIdentifier(String script, int start) {
    final int end = script.indexOf(']', start + 1);
    return end == -1 ? script.length : end + 1;
  }
}
