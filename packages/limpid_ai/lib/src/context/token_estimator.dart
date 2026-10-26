/// Estimation du nombre de tokens d'un texte.
///
/// Aucun tokenizer n'est embarqué : l'estimation par heuristique est suffisante
/// pour dimensionner une fenêtre de contexte et un budget. Les appelants qui
/// disposent d'un vrai tokenizer peuvent fournir leur propre implémentation.
abstract class TokenEstimator {
  /// Estime le nombre de tokens d'un texte.
  int estimate(String text);
}

/// Estimateur heuristique : environ quatre caractères par token.
class HeuristicTokenEstimator implements TokenEstimator {
  /// Crée un estimateur.
  const HeuristicTokenEstimator({this.charactersPerToken = 4});

  /// Nombre moyen de caractères par token.
  final int charactersPerToken;

  @override
  int estimate(String text) {
    if (text.isEmpty) {
      return 0;
    }
    final int divisor = charactersPerToken <= 0 ? 1 : charactersPerToken;
    return (text.length / divisor).ceil();
  }
}
