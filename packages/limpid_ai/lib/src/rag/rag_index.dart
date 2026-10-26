/// Document indexé dans un index de recherche vectorielle.
class RagDocument {
  /// Crée un document indexable.
  const RagDocument({
    required this.id,
    required this.text,
    required this.embedding,
    this.metadata = const <String, String>{},
  });

  /// Identifiant stable du document (scène, chapitre).
  final String id;

  /// Texte source du document.
  final String text;

  /// Vecteur d'embedding du texte.
  final List<double> embedding;

  /// Métadonnées libres (chapitre, scène, personnage).
  final Map<String, String> metadata;

  /// Copie modifiée de ce document.
  RagDocument copyWith({
    String? id,
    String? text,
    List<double>? embedding,
    Map<String, String>? metadata,
  }) {
    return RagDocument(
      id: id ?? this.id,
      text: text ?? this.text,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Résultat d'une recherche vectorielle.
class RagSearchResult {
  /// Crée un résultat de recherche.
  const RagSearchResult({required this.document, required this.score});

  /// Document correspondant.
  final RagDocument document;

  /// Score de similarité (cosinus, entre -1 et 1).
  final double score;

  @override
  String toString() =>
      'RagSearchResult(${document.id}, score: ${score.toStringAsFixed(4)})';
}

/// Index de recherche vectorielle sur le manuscrit.
///
/// L'implémentation de production (pgvector) est fournie par l'API Limpid ;
/// ce package fournit l'interface et une implémentation de référence en
/// mémoire, utilisable hors-ligne.
abstract class RagIndex {
  /// Ajoute ou remplace un document.
  Future<void> upsert(RagDocument document);

  /// Supprime un document.
  Future<void> delete(String id);

  /// Vide l'index.
  Future<void> clear();

  /// Recherche les documents les plus proches d'un vecteur.
  ///
  /// Les résultats sont triés par score décroissant et tronqués à [limit].
  Future<List<RagSearchResult>> searchByEmbedding(
    List<double> queryEmbedding, {
    int limit = 5,
    double minScore = 0,
  });
}

/// Fournisseur d'embeddings.
///
/// L'API Limpid fournit une implémentation based sur un modèle d'embeddings ;
/// ce package fournit une implémentation de référence déterministe et
/// hors-ligne, suffisante pour un index de démonstration.
abstract class AiEmbeddingProvider {
  /// Nombre de dimensions des vecteurs produits.
  int get dimensions;

  /// Calcule l'embedding d'un texte.
  Future<List<double>> embed(String text);
}
