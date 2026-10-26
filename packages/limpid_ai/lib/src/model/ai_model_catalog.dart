import 'package:limpid_ai/src/model/ai_provider_kind.dart';

/// Palier de modèle, du plus exigeant au plus économe.
enum AiModelTier {
  /// Qualité maximale : structuration, cohérence, analyse poussée.
  quality,

  /// Équilibre qualité / coût : usage quotidien.
  balanced,

  /// Rapidité et coût : tâches courtes, résumé, détection.
  fast;

  /// Nom stable du palier, utilisé dans les métadonnées.
  String get wireName => name;
}

/// Catalogue des modèles par défaut et bascule de modèle.
///
/// Les identifiants sont ceux des fournisseurs visés ; ils sont surchargeables
/// à chaque appel via [AiRequestOptions.model].
class AiModelCatalog {
  const AiModelCatalog._();

  /// Claude Opus — qualité.
  static const String anthropicQuality = 'claude-opus-5-5';

  /// Claude Sonnet — équilibre.
  static const String anthropicBalanced = 'claude-sonnet-5-5';

  /// Claude Haiku — rapide et économique.
  static const String anthropicFast = 'claude-haiku-5-5';

  /// Modèle de qualité par défaut pour un endpoint compatible OpenAI.
  static const String openAiCompatibleQuality = 'gpt-4o';

  /// Modèle équilibré par défaut pour un endpoint compatible OpenAI.
  static const String openAiCompatibleBalanced = 'gpt-4o-mini';

  /// Modèle rapide par défaut pour un endpoint compatible OpenAI.
  static const String openAiCompatibleFast = 'gpt-4o-mini';

  /// Modèle local de qualité par défaut (Ollama).
  static const String ollamaQuality = 'llama3.1';

  /// Modèle local équilibré par défaut (Ollama).
  static const String ollamaBalanced = 'llama3.1';

  /// Modèle local rapide par défaut (Ollama).
  static const String ollamaFast = 'qwen2.5';

  /// Modèle par défaut pour une fournisseur et un palier donnés.
  static String defaultModel(AiProviderKind kind, AiModelTier tier) {
    switch (kind) {
      case AiProviderKind.anthropic:
        return switch (tier) {
          AiModelTier.quality => anthropicQuality,
          AiModelTier.balanced => anthropicBalanced,
          AiModelTier.fast => anthropicFast,
        };
      case AiProviderKind.openaiCompatible:
        return switch (tier) {
          AiModelTier.quality => openAiCompatibleQuality,
          AiModelTier.balanced => openAiCompatibleBalanced,
          AiModelTier.fast => openAiCompatibleFast,
        };
      case AiProviderKind.ollama:
        return switch (tier) {
          AiModelTier.quality => ollamaQuality,
          AiModelTier.balanced => ollamaBalanced,
          AiModelTier.fast => ollamaFast,
        };
    }
  }
}
