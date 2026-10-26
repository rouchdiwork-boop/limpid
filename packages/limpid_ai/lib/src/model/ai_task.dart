import 'package:limpid_ai/src/model/ai_pricing.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';

/// Catégorie de coût d'une tâche IA.
enum AiCostCategory {
  /// Aucun coût fournisseur (mode local, ou tâche purement déterministe).
  free,

  /// Coût négligeable : résumé, détection, analyse de lisibilité.
  cheap,

  /// Coût standard : réécriture, RAG, beat sheet.
  standard,

  /// Coût élevé : génération structurante (plan, personnages, monde).
  premium;

  /// Nom stable de la catégorie.
  String get wireName => name;
}

/// Description complète d'une tâche IA.
class AiTask {
  const AiTask({
    required this.key,
    required this.label,
    required this.systemPrompt,
    required this.userTemplate,
    required this.maxTokens,
    required this.temperature,
    required this.recommendedProvider,
    required this.recommendedModel,
    required this.costCategory,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    this.supportsStreaming = true,
  });

  /// Identifiant stable de la tâche (ex. `rewrite_inline`).
  final String key;

  /// Libellé en français, destiné aux libellés d'interface.
  final String label;

  /// Consigne système : posture, garde-fous, format de sortie.
  final String systemPrompt;

  /// Modèle utilisateur, avec des emplacements `{{cle}}`.
  final String userTemplate;

  /// Plafond de tokens de sortie.
  final int maxTokens;

  /// Température par défaut.
  final double temperature;

  /// Fournisseur recommandée.
  final AiProviderKind recommendedProvider;

  /// Modèle recommandé.
  final String recommendedModel;

  /// Catégorie de coût.
  final AiCostCategory costCategory;

  /// Volume de tokens entrants estimé pour une exécution typique.
  final int estimatedInputTokens;

  /// Volume de tokens sortants estimé pour une exécution typique.
  final int estimatedOutputTokens;

  /// Indique si la tâche a du sens en streaming.
  final bool supportsStreaming;

  /// Total des tokens estimés pour une exécution typique.
  int get estimatedTotalTokens => estimatedInputTokens + estimatedOutputTokens;

  /// Coût estimé en dollars pour une exécution typique.
  double get estimatedCostUsd {
    return AiPricing.estimateCostUsd(
      recommendedModel,
      inputTokens: estimatedInputTokens,
      outputTokens: estimatedOutputTokens,
    );
  }
}
