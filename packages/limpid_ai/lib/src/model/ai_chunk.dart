import 'package:limpid_ai/src/model/ai_usage.dart';

/// Fragment de réponse émis pendant un appel en streaming.
class AiChunk {
  /// Crée un fragment.
  const AiChunk({
    required this.text,
    this.usage,
    this.isDone = false,
    this.model,
  });

  /// Fragment vide signalant la fin du flux.
  const AiChunk.done({this.usage, this.model}) : text = '', isDone = true;

  /// Texte incremental (vide pour le fragment de fin).
  final String text;

  /// Consommation de tokens, renseignée sur le dernier fragment.
  final AiUsage? usage;

  /// Vrai pour le dernier fragment du flux.
  final bool isDone;

  /// Modèle ayant produit le flux.
  final String? model;

  /// Copie modifiée de ce fragment.
  AiChunk copyWith({
    String? text,
    AiUsage? usage,
    bool? isDone,
    String? model,
  }) {
    return AiChunk(
      text: text ?? this.text,
      usage: usage ?? this.usage,
      isDone: isDone ?? this.isDone,
      model: model ?? this.model,
    );
  }

  @override
  String toString() => 'AiChunk("${text.length} caractères", done: $isDone)';
}
