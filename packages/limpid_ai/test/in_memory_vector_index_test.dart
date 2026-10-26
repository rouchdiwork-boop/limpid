import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryVectorIndex', () {
    test('classe les documents par similarité décroissante', () async {
      final InMemoryVectorIndex index = InMemoryVectorIndex();
      await index.upsert(
        const RagDocument(
          id: 'orthogonal',
          text: 'zéro',
          embedding: <double>[0, 1],
        ),
      );
      await index.upsert(
        const RagDocument(
          id: 'proche',
          text: 'proche',
          embedding: <double>[0.9, 0.1],
        ),
      );
      await index.upsert(
        const RagDocument(
          id: 'exact',
          text: 'exact',
          embedding: <double>[1, 0],
        ),
      );

      final List<RagSearchResult> results = await index.searchByEmbedding(
        <double>[1, 0],
        limit: 3,
      );

      expect(
        results.map((RagSearchResult result) => result.document.id),
        <String>['exact', 'proche', 'orthogonal'],
      );
      expect(results.first.score, closeTo(1, 0.0001));
      expect(results[1].score, greaterThan(results[2].score));
    });

    test('écarte les documents sous le seuil minimal', () async {
      final InMemoryVectorIndex index = InMemoryVectorIndex();
      await index.upsert(
        const RagDocument(
          id: 'exact',
          text: 'exact',
          embedding: <double>[1, 0],
        ),
      );
      await index.upsert(
        const RagDocument(
          id: 'orthogonal',
          text: 'zéro',
          embedding: <double>[0, 1],
        ),
      );

      final List<RagSearchResult> results = await index.searchByEmbedding(
        <double>[1, 0],
        minScore: 0.5,
      );

      expect(results, hasLength(1));
      expect(results.single.document.id, 'exact');
    });

    test('respecte la limite de résultats', () async {
      final InMemoryVectorIndex index = InMemoryVectorIndex();
      await index.upsert(
        const RagDocument(id: 'a', text: 'a', embedding: <double>[1, 0]),
      );
      await index.upsert(
        const RagDocument(id: 'b', text: 'b', embedding: <double>[0.9, 0.1]),
      );
      await index.upsert(
        const RagDocument(id: 'c', text: 'c', embedding: <double>[0.8, 0.2]),
      );

      final List<RagSearchResult> results = await index.searchByEmbedding(
        <double>[1, 0],
        limit: 2,
      );

      expect(results, hasLength(2));
    });

    test('remplace, supprime et vide l\'index', () async {
      final InMemoryVectorIndex index = InMemoryVectorIndex();
      await index.upsert(
        const RagDocument(id: 'a', text: 'a', embedding: <double>[1, 0]),
      );
      await index.upsert(
        const RagDocument(id: 'a', text: 'a2', embedding: <double>[1, 0]),
      );
      expect(index.length, 1);
      expect(index.documents.single.text, 'a2');

      await index.delete('a');
      expect(index.length, 0);

      await index.upsert(
        const RagDocument(id: 'b', text: 'b', embedding: <double>[0, 1]),
      );
      await index.clear();
      expect(index.length, 0);
    });

    test('la similarité cosinus est nulle pour des vecteurs nuls', () {
      expect(
        InMemoryVectorIndex.cosineSimilarity(<double>[0, 0], <double>[1, 0]),
        0,
      );
      expect(
        InMemoryVectorIndex.cosineSimilarity(<double>[1, 0], <double>[1, 0, 0]),
        0,
      );
    });

    test('recherche par texte avec l\'embedder de référence', () async {
      const HashingEmbeddingProvider embedder = HashingEmbeddingProvider();
      final InMemoryVectorIndex index = InMemoryVectorIndex(
        embeddingProvider: embedder,
      );
      await index.upsert(
        RagDocument(
          id: 'scene-1',
          text: 'Le train arrive en gare sous la pluie battante.',
          embedding: embedder.embedSync(
            'Le train arrive en gare sous la pluie battante.',
          ),
        ),
      );
      await index.upsert(
        RagDocument(
          id: 'scene-2',
          text: 'Le vieux.port était désert à cette heure.',
          embedding: embedder.embedSync(
            'Le vieux port était désert à cette heure.',
          ),
        ),
      );

      final List<RagSearchResult> results = await index.search(
        'train gare pluie',
        limit: 1,
      );

      expect(results, hasLength(1));
      expect(results.single.document.id, 'scene-1');
    });
  });
}
