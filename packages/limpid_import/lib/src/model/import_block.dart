/// Le genre d'un bloc lu dans un manuscrit.
///
/// L'import ne confond jamais un paragraphe et un element de liste : une
/// liste Markdown devient plusieurs blocs, pas un seul paragraphe colle.
enum ImportedBlockType {
  /// Un paragraphe de prose.
  paragraph,

  /// Un element de liste, ordonnee ou non.
  listItem,

  /// Une citation en bloc.
  quote,

  /// Un bloc de code preformate.
  code,
}

/// Un bloc de texte lu dans un manuscrit.
///
/// Le bloc est immuable : l'import ne le modifie jamais apres sa lecture.
final class ImportedBlock {
  /// Cree un bloc.
  const ImportedBlock({
    required this.type,
    required this.text,
    this.level,
    this.language,
    this.isOrdered = false,
  });

  /// Le genre du bloc.
  final ImportedBlockType type;

  /// Le texte du bloc.
  final String text;

  /// La profondeur d'un element de liste (1 pour le premier niveau).
  ///
  /// Vaut `null` pour les autres genres de blocs.
  final int? level;

  /// Le langage d'un bloc de code, quand le fichier source le declare.
  ///
  /// Vaut `null` quand le langage est inconnu : l'import ne devine pas.
  final String? language;

  /// Whether the item belongs to an ordered list.
  ///
  /// Vaut `false` pour les blocs qui ne sont pas des elements de liste.
  final bool isOrdered;

  /// Le nombre de mots du bloc.
  int get wordCount => _wordsOf(text);

  /// Une copie du bloc avec les champs remplaces.
  ImportedBlock copyWith({
    ImportedBlockType? type,
    String? text,
    int? level,
    String? language,
    bool? isOrdered,
  }) {
    return ImportedBlock(
      type: type ?? this.type,
      text: text ?? this.text,
      level: level ?? this.level,
      language: language ?? this.language,
      isOrdered: isOrdered ?? this.isOrdered,
    );
  }

  @override
  String toString() => 'ImportedBlock(${type.name}, $text)';

  static int _wordsOf(String text) {
    final List<String> words = text
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
    return words.length;
  }
}
