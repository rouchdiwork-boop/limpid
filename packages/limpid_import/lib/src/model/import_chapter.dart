import 'import_scene.dart';

/// Un chapitre lu dans un manuscrit.
///
/// Le chapitre porte le niveau de son titre (1, 2 ou 3) : le niveau dit
/// whether the title names a part, a chapter or a section. Les chapitres
/// forment une liste plate et ordonnee : le niveau porte la hierarchie, la
/// liste porte l'ordre.
final class ImportedChapter {
  /// Cree un chapitre.
  const ImportedChapter({
    required this.title,
    required this.level,
    required this.scenes,
  });

  /// Le titre du chapitre.
  final String title;

  /// Le niveau du titre : 1, 2 ou 3.
  final int level;

  /// Les scenes du chapitre, dans l'ordre de lecture.
  final List<ImportedScene> scenes;

  /// Le nombre de scenes du chapitre.
  int get sceneCount => scenes.length;

  /// Le nombre de blocs du chapitre.
  int get blockCount => scenes.fold<int>(
    0,
    (int total, ImportedScene scene) => total + scene.blockCount,
  );

  /// Le nombre de mots du chapitre.
  int get wordCount => scenes.fold<int>(
    0,
    (int total, ImportedScene scene) => total + scene.wordCount,
  );

  /// Une copie du chapitre avec les champs remplaces.
  ImportedChapter copyWith({
    String? title,
    int? level,
    List<ImportedScene>? scenes,
  }) {
    return ImportedChapter(
      title: title ?? this.title,
      level: level ?? this.level,
      scenes: scenes ?? this.scenes,
    );
  }

  @override
  String toString() => 'ImportedChapter($title, niveau $level)';
}
