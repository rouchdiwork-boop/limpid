import 'dart:math' as math;

import 'package:limpid_ai/src/rag/rag_index.dart';

/// Index vectoriel en mémoire, avec similarité cosinus.
///
/// Implémentation de référence : utile hors-ligne, dans les tests et pour un
/// petit manuscrit. L'API Limpid fournit une implémentation persistée sur
/// pgvector.
class InMemoryVectorIndex implements RagIndex {
  /// Crée un index en mémoire.
  InMemoryVectorIndex({this.embeddingProvider});

  /// Fournisseur d'embeddings, utilisé par [search].
  final AiEmbeddingProvider? embeddingProvider;

  final Map<String, RagDocument> _documents = <String, RagDocument>{};

  /// Nombre de documents indexés.
  int get length => _documents.length;

  /// Tous les documents indexés.
  List<RagDocument> get documents => _documents.values.toList(growable: false);

  @override
  Future<void> upsert(RagDocument document) async {
    _documents[document.id] = document;
  }

  @override
  Future<void> delete(String id) async {
    _documents.remove(id);
  }

  @override
  Future<void> clear() async {
    _documents.clear();
  }

  /// Recherche à partir d'un texte, en calculant son embedding.
  ///
  /// Lève [StateError] si aucun fournisseur d'embeddings n'est configuré.
  Future<List<RagSearchResult>> search(
    String query, {
    int limit = 5,
    double minScore = 0,
  }) async {
    final AiEmbeddingProvider? provider = embeddingProvider;
    if (provider == null) {
      throw StateError(
        'Aucun fournisseur d\'embeddings configuré pour cet index.',
      );
    }
    final List<double> embedding = await provider.embed(query);
    return searchByEmbedding(embedding, limit: limit, minScore: minScore);
  }

  @override
  Future<List<RagSearchResult>> searchByEmbedding(
    List<double> queryEmbedding, {
    int limit = 5,
    double minScore = 0,
  }) async {
    if (limit <= 0) {
      return const <RagSearchResult>[];
    }
    final List<RagSearchResult> results = <RagSearchResult>[];
    for (final RagDocument document in _documents.values) {
      final double score = cosineSimilarity(queryEmbedding, document.embedding);
      if (score < minScore) {
        continue;
      }
      results.add(RagSearchResult(document: document, score: score));
    }
    results.sort((RagSearchResult a, RagSearchResult b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.document.id.compareTo(b.document.id);
    });
    return results.take(limit).toList(growable: false);
  }

  /// Similarité cosinus entre deux vecteurs.
  ///
  /// Renvoie 0 si l'un des vecteurs est nul ou de dimensions différentes.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || a.length != b.length) {
      return 0;
    }
    double dot = 0;
    double normA = 0;
    double normB = 0;
    for (int index = 0; index < a.length; index++) {
      dot += a[index] * b[index];
      normA += a[index] * a[index];
      normB += b[index] * b[index];
    }
    if (normA <= 0 || normB <= 0) {
      return 0;
    }
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
