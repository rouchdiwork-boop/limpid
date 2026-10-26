import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

void main() {
  const AiTaskRegistry registry = AiTaskRegistry();

  group('AiTaskRegistry', () {
    test('déclare les quatorze tâches attendues', () {
      expect(registry.length, 14);
      expect(
        registry.keys,
        containsAll(<String>[
          AiTaskKeys.rewriteInline,
          AiTaskKeys.continueText,
          AiTaskKeys.generateOutline,
          AiTaskKeys.generateCharacters,
          AiTaskKeys.generateWorld,
          AiTaskKeys.summarize,
          AiTaskKeys.queryBook,
          AiTaskKeys.checkConsistency,
          AiTaskKeys.analyzeStyle,
          AiTaskKeys.detectCliches,
          AiTaskKeys.generateCover,
          AiTaskKeys.generateBeatSheet,
          AiTaskKeys.analyzeReadability,
          AiTaskKeys.translateText,
        ]),
      );
    });

    test('chaque tâche est complète et cohérente', () {
      for (final AiTask task in registry.all) {
        expect(task.key, isNotEmpty, reason: 'clé vide');
        expect(task.label, isNotEmpty, reason: '${task.key} : libellé vide');
        expect(
          task.systemPrompt.trim().length,
          greaterThan(80),
          reason: '${task.key} : consigne système trop courte',
        );
        expect(
          task.userTemplate.trim().length,
          greaterThan(40),
          reason: '${task.key} : modèle utilisateur trop court',
        );
        expect(task.maxTokens, greaterThan(0), reason: '${task.key}');
        expect(task.temperature, inInclusiveRange(0, 2), reason: '${task.key}');
        expect(
          task.estimatedInputTokens,
          greaterThan(0),
          reason: '${task.key} : estimation d\'entrée absente',
        );
        expect(
          task.estimatedOutputTokens,
          greaterThan(0),
          reason: '${task.key} : estimation de sortie absente',
        );
        expect(task.estimatedTotalTokens, greaterThan(0));
      }
    });

    test('chaque tâche recommande un modèle connu du catalogue', () {
      for (final AiTask task in registry.all) {
        expect(
          AiModelCatalog.defaultModel(
            task.recommendedProvider,
            AiModelTier.balanced,
          ),
          isNotEmpty,
        );
        expect(task.recommendedModel, isNotEmpty, reason: '${task.key}');
      }
    });

    test('les modèles de référence sont les trois paliers Anthropic', () {
      expect(AiModelCatalog.anthropicQuality, 'claude-opus-5-5');
      expect(AiModelCatalog.anthropicBalanced, 'claude-sonnet-5-5');
      expect(AiModelCatalog.anthropicFast, 'claude-haiku-5-5');
      expect(
        AiModelCatalog.defaultModel(
          AiProviderKind.anthropic,
          AiModelTier.quality,
        ),
        'claude-opus-5-5',
      );
      expect(
        AiModelCatalog.defaultModel(AiProviderKind.anthropic, AiModelTier.fast),
        'claude-haiku-5-5',
      );
    });

    test('lève une erreur sur une clé inconnue', () {
      expect(registry.find('inconnue'), isNull);
      expect(() => registry.require('inconnue'), throwsArgumentError);
    });

    test('les modèles de prompt ne contiennent aucun texte d\'exemple', () {
      for (final AiTask task in registry.all) {
        final String corpus = '${task.systemPrompt}\n${task.userTemplate}'
            .toLowerCase();
        expect(corpus, isNot(contains('lorem')));
        expect(corpus, isNot(contains('ipsum')));
        expect(corpus, isNot(contains('foo bar')));
      }
    });

    test('chaque tâche structurante expose des emplacements de modèle', () {
      final AiTask outline = registry.require(AiTaskKeys.generateOutline);
      expect(
        PromptRenderer.placeholdersOf(outline.userTemplate),
        containsAll(<String>['{{concept}}', '{{genre}}']),
      );
    });
  });

  group('PromptRenderer', () {
    test('remplace les emplacements fournis', () {
      const String template = 'Bonjour {{nom}}, voici {{sujet}}.';
      final String rendered = PromptRenderer.render(template, <String, String>{
        'nom': 'Camille',
        'sujet': 'le manuscrit',
      });
      expect(rendered, 'Bonjour Camille, voici le manuscrit.');
    });

    test('refuse un modèle incomplet', () {
      expect(
        () => PromptRenderer.render('Bonjour {{nom}}.', <String, String>{}),
        throwsArgumentError,
      );
    });
  });

  group('AiPricing', () {
    test('estime le coût à partir du volume de tokens', () {
      final double cost = AiPricing.estimateCostUsd(
        'claude-sonnet-5-5',
        inputTokens: 1000000,
        outputTokens: 1000000,
      );
      expect(cost, closeTo(18, 0.0001));
    });

    test('renvoie zéro pour un modèle au tarif inconnu', () {
      expect(
        AiPricing.estimateCostUsd(
          'modele-inconnu',
          inputTokens: 1000,
          outputTokens: 1000,
        ),
        0,
      );
    });
  });
}
