/// Tarification d'un modèle, exprimée par million de tokens.
///
/// Les tarifs ci-dessous sont des **estimations par défaut** : ils servent au
/// pilotage des coûts et doivent être alignés sur la grille tarifaire en
/// vigueur. Un modèle absent de la table est considéré comme gratuit
/// (coût estimé à 0), ce qui est le cas du mode local Ollama.
class AiModelPricing {
  const AiModelPricing({
    required this.inputUsdPerMillion,
    required this.outputUsdPerMillion,
  });

  /// Prix du token entrant, en dollars par million.
  final double inputUsdPerMillion;

  /// Prix du token sortant, en dollars par million.
  final double outputUsdPerMillion;

  /// Nombre de tokens dans un million.
  static const double tokensPerMillion = 1000000;

  /// Estime le coût en dollars d'un appel.
  double estimateCostUsd({
    required int inputTokens,
    required int outputTokens,
  }) {
    final double inputCost =
        (inputTokens / tokensPerMillion) * inputUsdPerMillion;
    final double outputCost =
        (outputTokens / tokensPerMillion) * outputUsdPerMillion;
    return inputCost + outputCost;
  }
}

/// Table de tarification et helpers d'estimation de coût.
class AiPricing {
  const AiPricing._();

  /// Tarifs par défaut, indexés par identifiant de modèle.
  static const Map<String, AiModelPricing> table = <String, AiModelPricing>{
    'claude-opus-5-5': AiModelPricing(
      inputUsdPerMillion: 15,
      outputUsdPerMillion: 75,
    ),
    'claude-sonnet-5-5': AiModelPricing(
      inputUsdPerMillion: 3,
      outputUsdPerMillion: 15,
    ),
    'claude-haiku-5-5': AiModelPricing(
      inputUsdPerMillion: 0.8,
      outputUsdPerMillion: 4,
    ),
  };

  /// Tarif d'un modèle, ou `null` si le modèle n'est pas référencé.
  static AiModelPricing? pricingFor(String model) => table[model];

  /// Coût estimé en dollars pour un couple de volumes de tokens.
  ///
  /// Renvoie 0 pour un modèle absent de la table (tarif inconnu ou mode
  /// local gratuit).
  static double estimateCostUsd(
    String model, {
    required int inputTokens,
    required int outputTokens,
  }) {
    final AiModelPricing? pricing = pricingFor(model);
    if (pricing == null) {
      return 0;
    }
    return pricing.estimateCostUsd(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}
