import 'package:limpid_ai/limpid_ai.dart';

/// Fournisseur factice : enregistre le prompt reçu et renvoie une réponse
/// préparée à l'avance.
class RecordingProvider implements LlmProvider {
  /// Crée un fournisseur factice.
  RecordingProvider({
    this.responseText = 'réponse simulée',
    this.usage = const AiUsage(inputTokens: 10, outputTokens: 5),
    this.model = 'claude-sonnet-5-5',
  });

  /// Texte renvoyé par [complete].
  final String responseText;

  /// Consommation annoncée.
  final AiUsage usage;

  /// Modèle annoncé.
  final String model;

  /// Prompt de la dernière requête.
  AiPrompt? lastPrompt;

  /// Options de la dernière requête.
  AiRequestOptions? lastOptions;

  /// Nombre d'appels à [complete].
  int completeCalls = 0;

  @override
  AiProviderKind get kind => AiProviderKind.anthropic;

  @override
  Future<AiResponse> complete(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async {
    completeCalls++;
    lastPrompt = prompt;
    lastOptions = options;
    return AiResponse(
      text: responseText,
      usage: usage,
      model: model,
      provider: kind,
    );
  }

  @override
  Stream<AiChunk> stream(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async* {
    lastPrompt = prompt;
    lastOptions = options;
    yield AiChunk(text: responseText, model: model);
    yield AiChunk.done(usage: usage, model: model);
  }
}

/// Compteur de consommation factice, à l'état piloté par le test.
class FakeUsageMeter implements UsageMeter {
  /// Crée un compteur factice.
  FakeUsageMeter({this.current = const AiUsageSnapshot.empty()});

  /// Consommation courante renvoyée par [snapshot].
  AiUsageSnapshot current;

  /// Consommations enregistrées.
  final List<AiUsage> recorded = <AiUsage>[];

  /// Étiquettes des enregistrements.
  final List<String> recordedFeatures = <String>[];

  @override
  Future<AiUsageSnapshot> snapshot(String userId) async => current;

  @override
  Future<void> record(
    AiUsage usage, {
    required String feature,
    required String userId,
    String? taskKey,
    AiProviderKind? provider,
  }) async {
    recorded.add(usage);
    recordedFeatures.add(feature);
  }
}
