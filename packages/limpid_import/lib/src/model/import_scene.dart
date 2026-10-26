import 'import_block.dart';

/// Une scene lue dans un manuscrit.
///
/// La scene est l'unite de travail de l'auteur : elle porte un titre et une
/// suite de blocs. Une scene n'est jamais vide : un lecteur qui n'a rien
/// trouve ne fabrique pas de scene.
final class ImportedScene {
  /// Cree une scene.
  const ImportedScene({required this.title, required this.blocks});

  /// Le titre de la scene.
  ///
  /// Vaut une chaine vide quand le fichier source ne nomme pas la scene.
  final String title;

  /// Les blocs de la scene, dans l'ordre de lecture.
  final List<ImportedBlock> blocks;

  /// Le nombre de blocs de la scene.
  int get blockCount => blocks.length;

  /// Le nombre de mots de la scene.
  int get wordCount => blocks.fold<int>(
    0,
    (int total, ImportedBlock block) => total + block.wordCount,
  );

  /// Une copie de la scene avec les champs remplaces.
  ImportedScene copyWith({String? title, List<ImportedBlock>? blocks}) {
    return ImportedScene(
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
    );
  }

  @override
  String toString() => 'ImportedScene($title, ${blocks.length} blocs)';
}
