/// Fournisseurs pris en charge par la passerelle.
enum AiProviderKind {
  /// Claude (fournisseur par défaut de Limpid).
  anthropic('anthropic'),

  /// Tout endpoint compatible OpenAI : OpenAI, Groq, Together, DeepSeek,
  /// LM Studio, Ollama via `/v1`.
  openaiCompatible('openaiCompatible'),

  /// Ollama en mode local (API native `/api/chat`).
  ollama('ollama');

  const AiProviderKind(this.wireName);

  /// Identifiant stable, utilisé dans les métadonnées et les compteurs.
  final String wireName;

  /// Retrouve une fournisseur à partir de son identifiant.
  ///
  /// Lève [ArgumentError] si l'identifiant est inconnu.
  static AiProviderKind fromName(String name) {
    for (final AiProviderKind kind in AiProviderKind.values) {
      if (kind.wireName == name) {
        return kind;
      }
    }
    throw ArgumentError.value(name, 'name', 'Fournisseur IA inconnue');
  }
}
