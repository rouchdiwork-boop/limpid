import 'package:limpid_ai/src/model/ai_chunk.dart';
import 'package:limpid_ai/src/model/ai_options.dart';
import 'package:limpid_ai/src/model/ai_prompt.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_response.dart';

/// Contrat commun à toutes les fournisseurs de modèles de langage.
///
/// Les appels non-streaming renvoient une [AiResponse] complète ; les appels
/// en streaming renvoient un flux de [AiChunk].
abstract class LlmProvider {
  /// Identifiant de la fournisseur.
  AiProviderKind get kind;

  /// Exécute un appel complet (sans streaming).
  Future<AiResponse> complete(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  });

  /// Exécute un appel en streaming.
  Stream<AiChunk> stream(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  });
}
