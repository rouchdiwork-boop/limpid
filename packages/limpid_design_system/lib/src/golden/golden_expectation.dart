import 'dart:io';

import 'package:flutter/foundation.dart';

/// Les attentes d'un temoin structurel, ecrites dans un fichier.
///
/// Le fichier porte une **section par theme**. Une section commence par une
/// ligne `@@ <theme>` et se termine a la section suivante. Les lignes qui
/// commentent le fichier commencent par `#`.
///
/// ```text
/// # Temoin structurel de LimpidBadge.
/// @@ paper
/// LimpidBadge
///   Semantics semanticsLabel="En cours"
/// ```
@immutable
class GoldenExpectation {
  /// Cree une attente.
  const GoldenExpectation({required this.sections});

  /// Les sections du fichier, par nom de theme.
  final Map<String, List<String>> sections;

  /// Les lignes attendues pour un theme.
  List<String> sectionOf(String name) => sections[name] ?? const <String>[];

  /// Une attente vide.
  static const GoldenExpectation empty = GoldenExpectation(
    sections: <String, List<String>>{},
  );
}

/// Le format des fichiers d'attente.
///
/// Le format est **textuel et line par ligne** : un diff du fichier dit
/// exactement ce qui a change dans le rendu, sans outil et sans
/// interpretation.
abstract final class GoldenExpectationFile {
  /// Le prefixe des sections.
  static const String _sectionPrefix = '@@ ';

  /// Le prefixe des commentaires.
  static const String _commentPrefix = '#';

  /// Lit les attentes d'un fichier.
  ///
  /// Un fichier absent donne une attente vide : le test signale alors
  /// l'absence du fichier plutot qu'une difference de lignes.
  static GoldenExpectation read(File file) {
    if (!file.existsSync()) {
      return GoldenExpectation.empty;
    }
    final Map<String, List<String>> sections = <String, List<String>>{};
    String? current;
    for (final String line in file.readAsLinesSync()) {
      if (line.startsWith(_sectionPrefix)) {
        current = line.substring(_sectionPrefix.length).trim();
        sections.putIfAbsent(current, () => <String>[]);
        continue;
      }
      // Les lignes vides separent les sections : elles ne portent aucune
      // information et ne doivent jamais compter comme une difference.
      if (current == null ||
          line.startsWith(_commentPrefix) ||
          line.trim().isEmpty) {
        continue;
      }
      sections[current]!.add(line);
    }
    return GoldenExpectation(
      sections: <String, List<String>>{
        for (final MapEntry<String, List<String>> entry in sections.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      },
    );
  }

  /// Ecrit les attentes dans un fichier.
  ///
  /// Les sections sont ecrites dans l'ordre demande : le fichier reste lisible
  /// et le diff reste lisible.
  static void write(
    File file,
    GoldenExpectation expectation, {
    required String title,
    required List<String> order,
  }) {
    final List<String> lines = <String>[
      '# $title',
      '# Genere par `flutter test --update-goldens` : ne pas editer a la main.',
      '',
    ];
    for (final String name in order) {
      lines.add('$_sectionPrefix$name');
      final List<String>? section = expectation.sections[name];
      if (section != null) {
        lines.addAll(section);
      }
      lines.add('');
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${lines.join('\n')}\n');
  }
}
