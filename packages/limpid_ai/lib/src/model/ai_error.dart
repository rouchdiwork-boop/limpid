/// Hiérarchie d'erreurs typées de la passerelle IA.
///
/// Chaque erreur porte :
/// - un [code] technique stable, en anglais,(destiné aux journaux et aux API) ;
/// - un [userMessage] en français, affichable tel quel dans l'interface.
sealed class AiError implements Exception {
  const AiError({
    required this.code,
    required this.userMessage,
    this.statusCode,
    this.providerName,
    this.details,
    this.retryAfter,
  });

  /// Code technique stable (ex. `ai_rate_limited`).
  final String code;

  /// Message utilisateur, en français.
  final String userMessage;

  /// Code HTTP d'origine, quand la fournisseur en a renvoyé un.
  final int? statusCode;

  /// Nom de la fournisseur à l'origine de l'erreur.
  final String? providerName;

  /// Contexte technique complémentaire (jamais de secret).
  final Map<String, String>? details;

  /// Délai avant nouvelle tentative, quand la fournisseur l'indique.
  final Duration? retryAfter;

  @override
  String toString() => '$runtimeType($code): $userMessage';
}

/// Panne du fournisseur : réseau, authentification, refus de service.
class AiProviderError extends AiError {
  const AiProviderError({
    required super.code,
    required super.userMessage,
    super.statusCode,
    super.providerName,
    super.details,
    super.retryAfter,
  });
}

/// Quota ou debit temporairement épuisé chez la fournisseur (HTTP 429).
class AiRateLimited extends AiProviderError {
  const AiRateLimited({
    super.providerName,
    super.statusCode,
    super.details,
    super.retryAfter,
  }) : super(
         code: 'ai_rate_limited',
         userMessage:
             'Le service IA est momentanément saturé. '
             'Réessayez dans un instant.',
       );
}

/// Délai dépassé avant réception de la réponse complète.
class AiTimeout extends AiProviderError {
  const AiTimeout({
    super.providerName,
    super.statusCode,
    super.details,
    Duration? timeout,
  }) : super(
         code: 'ai_timeout',
         userMessage:
             'Le service IA met trop de temps à répondre. '
             'Réessayez ou réduisez la taille du contexte.',
         retryAfter: timeout,
       );
}

/// Le modèle a refusé de produire la contenu demandée.
class AiSafetyRefusal extends AiProviderError {
  const AiSafetyRefusal({
    super.providerName,
    super.statusCode,
    super.details,
    String? reason,
  }) : super(
         code: 'ai_safety_refusal',
         userMessage:
             'Le service IA a refusé cette demande. '
             'Reformulez-la ou modifiez le passage concerné.',
       );
}

/// Réponse illisible ou incomplète renvoyée par la fournisseur.
class AiInvalidResponse extends AiProviderError {
  const AiInvalidResponse({
    super.providerName,
    super.statusCode,
    super.details,
    String? reason,
  }) : super(
         code: 'ai_invalid_response',
         userMessage:
             'La réponse du service IA est incomplète ou illisible. '
             'Réessayez.',
       );
}

/// Plafond de consommation atteint (par requête ou par jour).
class AiBudgetExceeded extends AiError {
  const AiBudgetExceeded({
    required this.limit,
    required this.limitKind,
    super.details,
  }) : super(
         code: 'ai_budget_exceeded',
         userMessage:
             'Le quota IA autorisé est atteint. '
             'Passez au palier supérieur ou attendez le prochain jour.',
       );

  /// Valeur du plafond atteint.
  final num limit;

  /// Nature du plafond : `request`, `daily_tokens` ou `daily_cost`.
  final String limitKind;
}
