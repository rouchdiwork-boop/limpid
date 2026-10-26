/// Passerelle IA multi-fournisseurs de Limpid.
///
/// Le package expose :
/// - une façade [AiClient] (`generate`, `stream`, `inline`, `query`) ;
/// - un contrat commun [LlmProvider] et trois fournisseurs : Anthropic,
///   compatible OpenAI, Ollama local ;
/// - un registre des quatorze tâches IA et leurs modèles de prompt ;
/// - un garde-fou de consommation ([BudgetGuard]) adossé à un [UsageMeter] ;
/// - un assembleur de contexte ([ContextBuilder]) et un index RAG local
///   ([RagIndex], [InMemoryVectorIndex]) ;
/// - une hiérarchie d'erreurs typées ([AiError]).
///
/// Aucun secret n'est stocké dans ce package : les clés d'API sont résolues
/// à l'exécution par un [AiCredentialStore], injecté par l'API.
library;

export 'package:limpid_ai/src/budget/budget_guard.dart';
export 'package:limpid_ai/src/budget/usage_meter.dart';
export 'package:limpid_ai/src/client/ai_client.dart';
export 'package:limpid_ai/src/context/context_builder.dart';
export 'package:limpid_ai/src/context/manuscript_context.dart';
export 'package:limpid_ai/src/context/token_estimator.dart';
export 'package:limpid_ai/src/model/ai_chunk.dart';
export 'package:limpid_ai/src/model/ai_error.dart';
export 'package:limpid_ai/src/model/ai_message.dart';
export 'package:limpid_ai/src/model/ai_model_catalog.dart';
export 'package:limpid_ai/src/model/ai_options.dart';
export 'package:limpid_ai/src/model/ai_pricing.dart';
export 'package:limpid_ai/src/model/ai_prompt.dart';
export 'package:limpid_ai/src/model/ai_provider_kind.dart';
export 'package:limpid_ai/src/model/ai_response.dart';
export 'package:limpid_ai/src/model/ai_task.dart';
export 'package:limpid_ai/src/model/ai_usage.dart';
export 'package:limpid_ai/src/model/credential_store.dart';
export 'package:limpid_ai/src/providers/anthropic_provider.dart';
export 'package:limpid_ai/src/providers/http_provider_base.dart';
export 'package:limpid_ai/src/providers/llm_provider.dart';
export 'package:limpid_ai/src/providers/ollama_provider.dart';
export 'package:limpid_ai/src/providers/openai_compatible_provider.dart';
export 'package:limpid_ai/src/providers/provider_json.dart';
export 'package:limpid_ai/src/providers/sse_decoder.dart';
export 'package:limpid_ai/src/rag/hashing_embedding_provider.dart';
export 'package:limpid_ai/src/rag/in_memory_vector_index.dart';
export 'package:limpid_ai/src/rag/rag_index.dart';
export 'package:limpid_ai/src/tasks/ai_task_keys.dart';
export 'package:limpid_ai/src/tasks/ai_task_registry.dart';
export 'package:limpid_ai/src/tasks/prompt_renderer.dart';
export 'package:limpid_ai/src/tasks/prompt_templates.dart';
export 'package:limpid_ai/src/tasks/prompt_templates_analysis.dart';
export 'package:limpid_ai/src/tasks/prompt_templates_characters.dart';
export 'package:limpid_ai/src/tasks/prompt_templates_planning.dart';
export 'package:limpid_ai/src/tasks/prompt_templates_rag.dart';
export 'package:limpid_ai/src/tasks/prompt_templates_text.dart';
