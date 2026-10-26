import 'package:limpid_ai/src/model/ai_model_catalog.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_task.dart';
import 'package:limpid_ai/src/tasks/ai_task_keys.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_analysis.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_characters.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_planning.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_rag.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_text.dart';

/// Registre des quatorze tâches IA de Limpid.
///
/// Chaque tâche décrit sa consigne système, son modèle utilisateur, son budget
/// de sortie, sa température, la fournisseur et le modèle recommandés, sa
/// catégorie de coût et les volumes de tokens estimés.
///
/// Les clés sont stables : elles servent d'identifiant de fonctionnalité dans
/// les compteurs de quota et les journaux.
class AiTaskRegistry {
  /// Crée un registre (la table des tâches est statique et immuable).
  const AiTaskRegistry();

  /// Table des tâches, indexée par clé.
  static const Map<String, AiTask> _tasks = <String, AiTask>{
    AiTaskKeys.rewriteInline: AiTask(
      key: AiTaskKeys.rewriteInline,
      label: 'Réécriture inline',
      systemPrompt: PromptTemplatesText.rewriteInlineSystem,
      userTemplate: PromptTemplatesText.rewriteInlineUser,
      maxTokens: 2000,
      temperature: 0.7,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 900,
      estimatedOutputTokens: 600,
    ),
    AiTaskKeys.continueText: AiTask(
      key: AiTaskKeys.continueText,
      label: 'Continuation assistée',
      systemPrompt: PromptTemplatesText.continueTextSystem,
      userTemplate: PromptTemplatesText.continueTextUser,
      maxTokens: 2000,
      temperature: 0.9,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 1400,
      estimatedOutputTokens: 900,
    ),
    AiTaskKeys.generateOutline: AiTask(
      key: AiTaskKeys.generateOutline,
      label: 'Génération de plan',
      systemPrompt: PromptTemplatesPlanning.generateOutlineSystem,
      userTemplate: PromptTemplatesPlanning.generateOutlineUser,
      maxTokens: 4000,
      temperature: 0.8,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicQuality,
      costCategory: AiCostCategory.premium,
      estimatedInputTokens: 1200,
      estimatedOutputTokens: 2600,
    ),
    AiTaskKeys.generateCharacters: AiTask(
      key: AiTaskKeys.generateCharacters,
      label: 'Génération de personnages',
      systemPrompt: PromptTemplatesCharacters.generateCharactersSystem,
      userTemplate: PromptTemplatesCharacters.generateCharactersUser,
      maxTokens: 4000,
      temperature: 0.8,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicQuality,
      costCategory: AiCostCategory.premium,
      estimatedInputTokens: 1200,
      estimatedOutputTokens: 2600,
    ),
    AiTaskKeys.generateWorld: AiTask(
      key: AiTaskKeys.generateWorld,
      label: 'Génération de monde',
      systemPrompt: PromptTemplatesPlanning.generateWorldSystem,
      userTemplate: PromptTemplatesPlanning.generateWorldUser,
      maxTokens: 4000,
      temperature: 0.8,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicQuality,
      costCategory: AiCostCategory.premium,
      estimatedInputTokens: 1200,
      estimatedOutputTokens: 2600,
    ),
    AiTaskKeys.summarize: AiTask(
      key: AiTaskKeys.summarize,
      label: 'Résumé de scène ou de chapitre',
      systemPrompt: PromptTemplatesText.summarizeSystem,
      userTemplate: PromptTemplatesText.summarizeUser,
      maxTokens: 1500,
      temperature: 0.4,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicFast,
      costCategory: AiCostCategory.cheap,
      estimatedInputTokens: 4000,
      estimatedOutputTokens: 700,
    ),
    AiTaskKeys.queryBook: AiTask(
      key: AiTaskKeys.queryBook,
      label: 'Interrogation du manuscrit',
      systemPrompt: PromptTemplatesRag.queryBookSystem,
      userTemplate: PromptTemplatesRag.queryBookUser,
      maxTokens: 2000,
      temperature: 0.3,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 6000,
      estimatedOutputTokens: 1000,
    ),
    AiTaskKeys.checkConsistency: AiTask(
      key: AiTaskKeys.checkConsistency,
      label: 'Contrôle de cohérence',
      systemPrompt: PromptTemplatesAnalysis.checkConsistencySystem,
      userTemplate: PromptTemplatesAnalysis.checkConsistencyUser,
      maxTokens: 2500,
      temperature: 0.2,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 8000,
      estimatedOutputTokens: 1300,
    ),
    AiTaskKeys.analyzeStyle: AiTask(
      key: AiTaskKeys.analyzeStyle,
      label: 'Analyse de style et profil de voix',
      systemPrompt: PromptTemplatesAnalysis.analyzeStyleSystem,
      userTemplate: PromptTemplatesAnalysis.analyzeStyleUser,
      maxTokens: 2500,
      temperature: 0.5,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 6000,
      estimatedOutputTokens: 1300,
    ),
    AiTaskKeys.detectCliches: AiTask(
      key: AiTaskKeys.detectCliches,
      label: 'Détection de clichés',
      systemPrompt: PromptTemplatesAnalysis.detectClichesSystem,
      userTemplate: PromptTemplatesAnalysis.detectClichesUser,
      maxTokens: 2000,
      temperature: 0.3,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicFast,
      costCategory: AiCostCategory.cheap,
      estimatedInputTokens: 5000,
      estimatedOutputTokens: 1000,
    ),
    AiTaskKeys.generateCover: AiTask(
      key: AiTaskKeys.generateCover,
      label: 'Génération de couverture',
      systemPrompt: PromptTemplatesRag.generateCoverSystem,
      userTemplate: PromptTemplatesRag.generateCoverUser,
      maxTokens: 1200,
      temperature: 0.9,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 700,
      estimatedOutputTokens: 800,
    ),
    AiTaskKeys.generateBeatSheet: AiTask(
      key: AiTaskKeys.generateBeatSheet,
      label: 'Beat sheet',
      systemPrompt: PromptTemplatesPlanning.generateBeatSheetSystem,
      userTemplate: PromptTemplatesPlanning.generateBeatSheetUser,
      maxTokens: 3000,
      temperature: 0.7,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 1500,
      estimatedOutputTokens: 1600,
    ),
    AiTaskKeys.analyzeReadability: AiTask(
      key: AiTaskKeys.analyzeReadability,
      label: 'Analyse de lisibilité',
      systemPrompt: PromptTemplatesAnalysis.analyzeReadabilitySystem,
      userTemplate: PromptTemplatesAnalysis.analyzeReadabilityUser,
      maxTokens: 1500,
      temperature: 0.2,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicFast,
      costCategory: AiCostCategory.cheap,
      estimatedInputTokens: 5000,
      estimatedOutputTokens: 800,
    ),
    AiTaskKeys.translateText: AiTask(
      key: AiTaskKeys.translateText,
      label: 'Traduction assistée',
      systemPrompt: PromptTemplatesText.translateTextSystem,
      userTemplate: PromptTemplatesText.translateTextUser,
      maxTokens: 4000,
      temperature: 0.3,
      recommendedProvider: AiProviderKind.anthropic,
      recommendedModel: AiModelCatalog.anthropicBalanced,
      costCategory: AiCostCategory.standard,
      estimatedInputTokens: 3000,
      estimatedOutputTokens: 2200,
    ),
  };

  /// Toutes les tâches, dans l'ordre d'insertion.
  List<AiTask> get all => _tasks.values.toList(growable: false);

  /// Toutes les clés de tâche.
  List<String> get keys => _tasks.keys.toList(growable: false);

  /// Nombre de tâches déclarées.
  int get length => _tasks.length;

  /// Retrouve une tâche par sa clé, ou `null` si elle n'existe pas.
  AiTask? find(String key) => _tasks[key];

  /// Retrouve une tâche par sa clé.
  ///
  /// Lève [ArgumentError] si la clé est inconnue.
  AiTask require(String key) {
    final AiTask? task = _tasks[key];
    if (task == null) {
      throw ArgumentError.value(key, 'key', 'Tâche IA inconnue');
    }
    return task;
  }
}
