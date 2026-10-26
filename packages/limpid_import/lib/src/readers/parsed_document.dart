import '../model/import_chapter.dart';
import '../model/import_skip.dart';

/// Le resultat brut de la lecture d'un fichier de manuscrit.
///
/// Le lecteur ne decide pas du titre final du manuscrit : il rend ce qu'il a
/// lu, et l'importateur tranche les replis (titre du fichier, nom generique
/// d'un chapitre sans titre).
final class ParsedDocument {
  /// Cree un document lu.
  const ParsedDocument({
    required this.chapters,
    this.title,
    this.skipped = const <ImportSkip>[],
  });

  /// Le titre interne du document, `null` quand le fichier n'en porte pas.
  final String? title;

  /// Les chapitres lus, dans l'ordre de lecture.
  final List<ImportedChapter> chapters;

  /// Les contenus que le lecteur a laisses de cote.
  final List<ImportSkip> skipped;

  /// Le nombre de blocs lus.
  int get blockCount => chapters.fold<int>(
    0,
    (int total, ImportedChapter chapter) => total + chapter.blockCount,
  );
}
