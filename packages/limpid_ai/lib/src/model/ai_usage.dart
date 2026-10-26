/// Consommation de tokens et coût estimé d'un appel IA.
class AiUsage {
  /// Crée une consumption mesurée.
  const AiUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.estimatedCostUsd = 0,
  });

  /// Consommation vide.
  const AiUsage.empty()
    : inputTokens = 0,
      outputTokens = 0,
      estimatedCostUsd = 0;

  /// Tokens entrants (prompt + contexte).
  final int inputTokens;

  /// Tokens sortants (réponse générée).
  final int outputTokens;

  /// Coût estimé en dollars américains (0 si le tarif est inconnu).
  final double estimatedCostUsd;

  /// Total des tokens consommés.
  int get totalTokens => inputTokens + outputTokens;

  /// Copie modifiée de cette consommation.
  AiUsage copyWith({
    int? inputTokens,
    int? outputTokens,
    double? estimatedCostUsd,
  }) {
    return AiUsage(
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      estimatedCostUsd: estimatedCostUsd ?? this.estimatedCostUsd,
    );
  }

  /// Cumule deux consommations.
  AiUsage operator +(AiUsage other) {
    return AiUsage(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      estimatedCostUsd: estimatedCostUsd + other.estimatedCostUsd,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AiUsage &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.estimatedCostUsd == estimatedCostUsd;
  }

  @override
  int get hashCode => Object.hash(inputTokens, outputTokens, estimatedCostUsd);

  @override
  String toString() =>
      'AiUsage(in: $inputTokens, out: $outputTokens, '
      'cost: \$${estimatedCostUsd.toStringAsFixed(6)})';
}
