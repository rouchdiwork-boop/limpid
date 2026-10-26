/// Priorité d'un bloc de contexte dans la fenêtre de tokens.
///
/// L'ordre de déclaration définit l'ordre de priorité décroissante : la scène
/// courante passe avant le chapitre, qui passe avant la bible, elle-même
/// avant les notes globales.
enum ContextPriority {
  /// Scène en cours d'écriture.
  currentScene,

  /// Chapitre courant, puis chapitres voisins.
  chapter,

  /// Bible du récit (personnages, lieux, chronologie).
  bible,

  /// Notes globales du projet.
  global;

  /// Nom stable de la priorité.
  String get wireName => name;
}

/// Bloc de contexte candidat à l'inclusion dans une fenêtre de tokens.
class ContextBlock {
  /// Crée un bloc de contexte.
  const ContextBlock({
    required this.id,
    required this.title,
    required this.text,
    required this.priority,
    this.distance = 0,
  });

  /// Identifiant stable du bloc (scène, chapitre, entrée de bible).
  final String id;

  /// Titre affiché dans le contexte assemblé.
  final String title;

  /// Contenu textuel.
  final String text;

  /// Priorité du bloc.
  final ContextPriority priority;

  /// Distance par rapport au point de travail courant (0 = le plus proche).
  final int distance;

  /// Copie modifiée de ce bloc.
  ContextBlock copyWith({
    String? id,
    String? title,
    String? text,
    ContextPriority? priority,
    int? distance,
  }) {
    return ContextBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      distance: distance ?? this.distance,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ContextBlock &&
        other.id == id &&
        other.title == title &&
        other.text == text &&
        other.priority == priority &&
        other.distance == distance;
  }

  @override
  int get hashCode => Object.hash(id, title, text, priority, distance);

  @override
  String toString() => 'ContextBlock($id, ${priority.wireName}, d$distance)';
}

/// Contexte d'un manuscrit, prêt à être assemblé.
class ManuscriptContext {
  /// Crée un contexte de manuscrit.
  const ManuscriptContext({
    this.currentScene,
    this.chapters = const <ContextBlock>[],
    this.bible = const <ContextBlock>[],
    this.globalNotes = const <ContextBlock>[],
  });

  /// Scène en cours d'écriture.
  final ContextBlock? currentScene;

  /// Chapitres du manuscrit, du plus proche au plus lointain.
  final List<ContextBlock> chapters;

  /// Éléments de la bible du récit.
  final List<ContextBlock> bible;

  /// Notes globales du projet.
  final List<ContextBlock> globalNotes;

  /// Tous les blocs, triés par priorité puis par distance.
  List<ContextBlock> get orderedBlocks {
    final List<ContextBlock> blocks = <ContextBlock>[
      if (currentScene != null) currentScene!,
      ...chapters,
      ...bible,
      ...globalNotes,
    ];
    final List<ContextBlock> sorted = List<ContextBlock>.of(blocks);
    sorted.sort(_compareBlocks);
    return sorted;
  }

  static int _compareBlocks(ContextBlock a, ContextBlock b) {
    final int byPriority = a.priority.index.compareTo(b.priority.index);
    if (byPriority != 0) {
      return byPriority;
    }
    final int byDistance = a.distance.compareTo(b.distance);
    if (byDistance != 0) {
      return byDistance;
    }
    return a.id.compareTo(b.id);
  }
}
