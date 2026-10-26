import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';

/// Réponse complète d'un modèle de langage.
class AiResponse {
  const AiResponse({
    required this.text,
    required this.usage,
    required this.model,
    required this.provider,
    this.stopReason,
  });

  /// Texte généré.
  final String text;

  /// Tokens consommés et coût estimé.
  final AiUsage usage;

  /// Modèle qui a réellement répondu.
  final String model;

  /// Fournisseur qui a répondu.
  final AiProviderKind provider;

  /// Raison d'arrêt renvoyée par la fournisseur.
  final String? stopReason;

  /// Copie modifiée de cette réponse.
  AiResponse copyWith({
    String? text,
    AiUsage? usage,
    String? model,
    AiProviderKind? provider,
    String? stopReason,
  }) {
    return AiResponse(
      text: text ?? this.text,
      usage: usage ?? this.usage,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      stopReason: stopReason ?? this.stopReason,
    );
  }

  @override
  String toString() =>
      'AiResponse($provider/$model, ${text.length} caractères)';
}
