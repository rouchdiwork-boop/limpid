import 'package:flutter/foundation.dart';

/// Une difference entre l'attente et le rendu.
///
/// Une difference porte soit la ligne attendue, soit la ligne obtenue, soit
/// les deux : une ligne ajoutee n'a pas d'attente, une ligne supprimee n'a
/// pas de rendu.
@immutable
class GoldenDifference {
  /// Cree une difference.
  const GoldenDifference({this.expected, this.actual});

  /// La ligne attendue, absente quand la ligne est ajoutee.
  final String? expected;

  /// La ligne obtenue, absente quand la ligne est supprimee.
  final String? actual;

  /// La difference, en une ligne lisible.
  String toLine() {
    final String expectedText = expected ?? '';
    final String actualText = actual ?? '';
    if (expected == null) {
      return '+ $actualText';
    }
    if (actual == null) {
      return '- $expectedText';
    }
    return '- $expectedText\n+ $actualText';
  }
}

/// Compare deux listes de lignes et rend leurs differences.
///
/// La comparaison passe par le plus long sous-sequence commune : le rapport
/// montre les lignes **changees**, pas un simple decalage de numeros.
abstract final class GoldenDiff {
  /// La taille maximale de la table de comparaison.
  ///
  /// Au-dela, la difference est raportee comme un bloc remplace : une table
  /// de comparaison enorme nuirait a la memoire du poste de test.
  static const int _maxComparisonSize = 400000;

  /// Compare l'attente et le rendu.
  static List<GoldenDifference> compare(
    List<String> expected,
    List<String> actual,
  ) {
    final int prefix = _commonPrefix(expected, actual);
    final int suffix = _commonSuffix(expected, actual, prefix);
    final List<String> middleExpected = expected.sublist(
      prefix,
      expected.length - suffix,
    );
    final List<String> middleActual = actual.sublist(
      prefix,
      actual.length - suffix,
    );
    if (middleExpected.length * middleActual.length > _maxComparisonSize) {
      return <GoldenDifference>[
        for (final String line in middleExpected)
          GoldenDifference(expected: line),
        for (final String line in middleActual) GoldenDifference(actual: line),
      ];
    }
    return _longestCommonSubsequence(middleExpected, middleActual);
  }

  /// Le nombre de lignes communes au debut des deux listes.
  static int _commonPrefix(List<String> expected, List<String> actual) {
    final int limit = expected.length < actual.length
        ? expected.length
        : actual.length;
    int index = 0;
    while (index < limit && expected[index] == actual[index]) {
      index++;
    }
    return index;
  }

  /// Le nombre de lignes communes a la fin des deux listes.
  static int _commonSuffix(
    List<String> expected,
    List<String> actual,
    int prefix,
  ) {
    final int limit = expected.length < actual.length
        ? expected.length
        : actual.length;
    int index = 0;
    while (index < limit - prefix &&
        expected[expected.length - 1 - index] ==
            actual[actual.length - 1 - index]) {
      index++;
    }
    return index;
  }

  /// Les differences entre deux listes, par plus long sous-sequence commune.
  static List<GoldenDifference> _longestCommonSubsequence(
    List<String> expected,
    List<String> actual,
  ) {
    final int rows = expected.length;
    final int columns = actual.length;
    final List<List<int>> table = List<List<int>>.generate(
      rows + 1,
      (_) => List<int>.filled(columns + 1, 0),
      growable: false,
    );
    for (int row = rows - 1; row >= 0; row--) {
      for (int column = columns - 1; column >= 0; column--) {
        table[row][column] = expected[row] == actual[column]
            ? table[row + 1][column + 1] + 1
            : (table[row + 1][column] > table[row][column + 1]
                  ? table[row + 1][column]
                  : table[row][column + 1]);
      }
    }
    final List<GoldenDifference> differences = <GoldenDifference>[];
    int row = 0;
    int column = 0;
    while (row < rows && column < columns) {
      if (expected[row] == actual[column]) {
        row++;
        column++;
        continue;
      }
      if (table[row + 1][column] >= table[row][column + 1]) {
        differences.add(GoldenDifference(expected: expected[row]));
        row++;
      } else {
        differences.add(GoldenDifference(actual: actual[column]));
        column++;
      }
    }
    while (row < rows) {
      differences.add(GoldenDifference(expected: expected[row]));
      row++;
    }
    while (column < columns) {
      differences.add(GoldenDifference(actual: actual[column]));
      column++;
    }
    return differences;
  }
}
