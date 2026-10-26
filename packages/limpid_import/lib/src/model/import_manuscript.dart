import 'import_chapter.dart';
import 'import_scene.dart';
import 'import_skip.dart';

/// Un manuscrit lu dans un fichier.
///
/// Le resultat d'un import n'est jamais un seul bloc : c'est une hierarchie
/// de chapitres, de scenes et de blocs, que l'auteur peut encore modifier.
final class ImportedManuscript {
  /// Cree un manuscrit.
  const ImportedManuscript({
    required this.title,
    required this.chapters,
    this.skipped = const <ImportSkip>[],
  });

  /// Le titre du manuscrit.
  final String title;

  /// Les chapitres du manuscrit, dans l'ordre de lecture.
  final List<ImportedChapter> chapters;

  /// Les contenus que l'import a laisses de cote.
  ///
  /// La liste est vide quand rien n'a ete perdu.
  final List<ImportSkip> skipped;

  /// Le nombre de chapitres du manuscrit.
  int get chapterCount => chapters.length;

  /// Le nombre de scenes du manuscrit.
  int get sceneCount => chapters.fold<int>(
    0,
    (int total, ImportedChapter chapter) => total + chapter.sceneCount,
  );

  /// Le nombre de blocs du manuscrit.
  int get blockCount => chapters.fold<int>(
    0,
    (int total, ImportedChapter chapter) => total + chapter.blockCount,
  );

  /// Le nombre de mots du manuscrit.
  int get wordCount => chapters.fold<int>(
    0,
    (int total, ImportedChapter chapter) => total + chapter.wordCount,
  );

  /// Les scenes du manuscrit, tous chapitres confondus.
  List<ImportedScene> get scenes => chapters
      .expand((ImportedChapter chapter) => chapter.scenes)
      .toList(growable: false);

  /// Une copie du manuscrit avec les champs remplaces.
  ImportedManuscript copyWith({
    String? title,
    List<ImportedChapter>? chapters,
    List<ImportSkip>? skipped,
  }) {
    return ImportedManuscript(
      title: title ?? this.title,
      chapters: chapters ?? this.chapters,
      skipped: skipped ?? this.skipped,
    );
  }

  @override
  String toString() =>
      'ImportedManuscript($title, $chapterCount chapitres, $sceneCount scenes)';
}
