import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:limpid_design_system/src/golden/golden_diff.dart';
import 'package:limpid_design_system/src/golden/golden_expectation.dart';

/// Le resultat de la comparaison d'un rendu et de son attente.
@immutable
class GoldenWitness {
  /// Cree un resultat.
  const GoldenWitness({
    required this.differences,
    required this.report,
    this.updatedFile,
  });

  /// Les differences trouvees entre l'attente et le rendu.
  final List<GoldenDifference> differences;

  /// Le rapport lisible des differences.
  final String report;

  /// Le fichier d'attente mis a jour, quand le temoin a ete regenere.
  final File? updatedFile;

  /// Le temoin tient : le rendu est celui attendu.
  bool get isMatching => differences.isEmpty;
}

/// Le temoin structurel : compare un rendu a une attente stockee.
///
/// L'attente est un fichier **textuel** : une section par theme, une ligne
/// par noeud du rendu. Le rapport dit le widget et la valeur qui ont change.
abstract final class GoldenWitnessTool {
  /// Compare le rendu a l'attente et rend le temoin.
  ///
  /// Quand [isUpdating] est vrai, l'attente est **reecrite** avec le rendu
  /// courant : c'est le chemin de la regeneration deliberée.
  static GoldenWitness check({
    required File file,
    required String title,
    required String section,
    required List<String> order,
    required List<String> actual,
    required bool isUpdating,
    String regenerateCommand = 'flutter test --update-goldens',
  }) {
    final GoldenExpectation expectation = GoldenExpectationFile.read(file);
    final bool isMissing = !file.existsSync();

    if (isUpdating) {
      final Map<String, List<String>> sections = <String, List<String>>{
        for (final MapEntry<String, List<String>> entry
            in expectation.sections.entries)
          entry.key: List<String>.of(entry.value),
      };
      sections[section] = List<String>.of(actual);
      GoldenExpectationFile.write(
        file,
        GoldenExpectation(
          sections: <String, List<String>>{
            for (final MapEntry<String, List<String>> entry in sections.entries)
              entry.key: List<String>.unmodifiable(entry.value),
          },
        ),
        title: title,
        order: order,
      );
      return GoldenWitness(
        differences: const <GoldenDifference>[],
        report: 'Temoin regenere : $file',
        updatedFile: file,
      );
    }

    if (isMissing) {
      return GoldenWitness(
        differences: <GoldenDifference>[
          for (final String line in actual) GoldenDifference(actual: line),
        ],
        report:
            'Le fichier d\'attente est absent : ${file.path}\n'
            'Regenerer l\'attente : $regenerateCommand',
      );
    }

    final List<GoldenDifference> differences = GoldenDiff.compare(
      expectation.sectionOf(section),
      actual,
    );
    if (differences.isEmpty) {
      return GoldenWitness(
        differences: const <GoldenDifference>[],
        report: 'Le temoin de « $title » ($section) tient.',
      );
    }
    return GoldenWitness(
      differences: differences,
      report: _reportOf(
        title: title,
        section: section,
        differences: differences,
        regenerateCommand: regenerateCommand,
      ),
    );
  }

  /// Le rapport lisible des differences.
  static String _reportOf({
    required String title,
    required String section,
    required List<GoldenDifference> differences,
    required String regenerateCommand,
  }) {
    final StringBuffer buffer = StringBuffer()
      ..writeln(
        'Le temoin structurel de « $title » differe de l\'attente '
        '(theme : $section).',
      )
      ..writeln();
    for (final GoldenDifference difference in differences) {
      buffer.writeln(difference.toLine());
    }
    buffer
      ..writeln()
      ..writeln(
        'Si le changement est voulu, regenerer l\'attente : '
        '$regenerateCommand',
      );
    return buffer.toString();
  }
}
