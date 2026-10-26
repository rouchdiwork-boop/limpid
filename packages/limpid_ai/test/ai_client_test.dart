import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

import 'helpers/fakes.dart';

void main() {
  AiClient buildClient({
    required RecordingProvider provider,
    FakeUsageMeter? meter,
    BudgetGuard? guard,
    RagIndex? ragIndex,
    AiEmbeddingProvider? embeddingProvider,
  }) {
    return AiClient.withProviders(
      <AiProviderKind, LlmProvider>{AiProviderKind.anthropic: provider},
      budgetGuard: guard,
      ragIndex: ragIndex,
      embeddingProvider: embeddingProvider,
    );
  }

  group('AiClient', () {
    test(
      'generate renvoie la réponse et applique les options de la tâche',
      () async {
        final RecordingProvider provider = RecordingProvider();
        final AiClient client = buildClient(provider: provider);

        final AiResponse response = await client.generate(
          AiPrompt.user('Bonjour'),
          task: const AiTaskRegistry().require(AiTaskKeys.rewriteInline),
        );

        expect(response.text, 'réponse simulée');
        expect(provider.lastOptions?.model, AiModelCatalog.anthropicBalanced);
        expect(provider.lastOptions?.maxTokens, 2000);
        expect(provider.lastOptions?.temperature, 0.7);
      },
    );

    test(
      'generate laisse les options explicites primer sur la tâche',
      () async {
        final RecordingProvider provider = RecordingProvider();
        final AiClient client = buildClient(provider: provider);

        await client.generate(
          AiPrompt.user('Bonjour'),
          task: const AiTaskRegistry().require(AiTaskKeys.rewriteInline),
          options: const AiRequestOptions(
            model: 'claude-haiku-5-5',
            maxTokens: 256,
          ),
        );

        expect(provider.lastOptions?.model, 'claude-haiku-5-5');
        expect(provider.lastOptions?.maxTokens, 256);
      },
    );

    test('inline construit le prompt de réécriture', () async {
      final RecordingProvider provider = RecordingProvider();
      final AiClient client = buildClient(provider: provider);

      await client.inline(
        const AiInlineRequest(
          action: AiInlineAction.changeTone,
          text: 'Il dit bonjour.',
          tone: 'plus distant',
        ),
      );

      final String prompt = provider.lastPrompt!.plainText;
      expect(prompt, contains('Il dit bonjour.'));
      expect(prompt, contains('plus distant'));
      expect(prompt, contains('Réécris ce passage dans le ton demandé'));
    });

    test('inline en traduction utilise la tâche de traduction', () async {
      final RecordingProvider provider = RecordingProvider();
      final AiClient client = buildClient(provider: provider);

      await client.inline(
        const AiInlineRequest(
          action: AiInlineAction.translate,
          text: 'Good morning.',
          targetLanguage: 'anglais',
        ),
      );

      expect(provider.lastOptions?.maxTokens, 4000);
      expect(provider.lastPrompt!.plainText, contains('Good morning.'));
    });

    test('query interroge le manuscrit via l\'index RAG', () async {
      final RecordingProvider provider = RecordingProvider();
      const HashingEmbeddingProvider embedder = HashingEmbeddingProvider();
      final InMemoryVectorIndex index = InMemoryVectorIndex(
        embeddingProvider: embedder,
      );
      await index.upsert(
        RagDocument(
          id: 'chapitre-1',
          text: 'Mara ouvre la porte du manoir.',
          embedding: embedder.embedSync('Mara ouvre la porte du manoir.'),
        ),
      );
      final AiClient client = buildClient(
        provider: provider,
        ragIndex: index,
        embeddingProvider: embedder,
      );

      await client.query(const AiQueryRequest(question: 'Que fait Mara ?'));

      final String prompt = provider.lastPrompt!.plainText;
      expect(prompt, contains('Que fait Mara ?'));
      expect(prompt, contains('Mara ouvre la porte du manoir.'));
    });

    test('query échoue explicitement sans index RAG', () async {
      final RecordingProvider provider = RecordingProvider();
      final AiClient client = buildClient(provider: provider);

      await expectLater(
        client.query(const AiQueryRequest(question: 'Que fait Mara ?')),
        throwsA(
          isA<AiProviderError>().having(
            (AiProviderError error) => error.code,
            'code',
            'ai_rag_unavailable',
          ),
        ),
      );
    });

    test('enregistre la consommation auprès du garde-fou', () async {
      final RecordingProvider provider = RecordingProvider();
      final FakeUsageMeter meter = FakeUsageMeter();
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 100000,
      );
      final AiClient client = buildClient(
        provider: provider,
        meter: meter,
        guard: guard,
      );

      await client.generate(
        AiPrompt.user('Bonjour'),
        tag: const AiCallTag(feature: 'rewrite_inline', userId: 'auteur-1'),
      );

      expect(meter.recorded, hasLength(1));
      expect(meter.recorded.single.totalTokens, 15);
      expect(meter.recordedFeatures.single, 'rewrite_inline');
    });

    test(
      'refuse un appel hors budget avant d\'interroger la fournisseur',
      () async {
        final RecordingProvider provider = RecordingProvider();
        final FakeUsageMeter meter = FakeUsageMeter();
        final BudgetGuard guard = BudgetGuard(
          meter: meter,
          maxTokensPerRequest: 10,
        );
        final AiClient client = buildClient(
          provider: provider,
          meter: meter,
          guard: guard,
        );

        await expectLater(
          client.generate(
            AiPrompt.user('Un texte assez long pour dépasser le plafond'),
            tag: const AiCallTag(feature: 'rewrite_inline', userId: 'auteur-1'),
          ),
          throwsA(isA<AiBudgetExceeded>()),
        );
        expect(provider.completeCalls, 0);
      },
    );

    test('stream émet les fragments puis enregistre la consommation', () async {
      final RecordingProvider provider = RecordingProvider();
      final FakeUsageMeter meter = FakeUsageMeter();
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 100000,
      );
      final AiClient client = buildClient(
        provider: provider,
        meter: meter,
        guard: guard,
      );

      final List<AiChunk> chunks = await client
          .stream(
            AiPrompt.user('Bonjour'),
            tag: const AiCallTag(feature: 'rewrite_inline', userId: 'auteur-1'),
          )
          .toList();

      expect(chunks, hasLength(2));
      expect(chunks.last.isDone, isTrue);
      expect(meter.recorded, hasLength(1));
    });

    test('runTask rend le modèle utilisateur de la tâche', () async {
      final RecordingProvider provider = RecordingProvider();
      final AiClient client = buildClient(provider: provider);
      const AiTaskRegistry registry = AiTaskRegistry();

      await client.runTask(
        registry.require(AiTaskKeys.generateOutline),
        <String, String>{
          'concept': 'Un récit maritime.',
          'genre': 'roman',
          'public': 'adultes',
          'format': 'trois parties',
          'consignes': 'fin ouverte',
        },
      );

      expect(provider.lastPrompt!.plainText, contains('Un récit maritime.'));
    });

    test('signale une fournisseur non configurée', () async {
      final AiClient client = AiClient.withProviders(
        const <AiProviderKind, LlmProvider>{},
      );

      await expectLater(
        client.generate(AiPrompt.user('Bonjour')),
        throwsA(
          isA<AiProviderError>().having(
            (AiProviderError error) => error.code,
            'code',
            'ai_provider_unavailable',
          ),
        ),
      );
    });
  });
}
