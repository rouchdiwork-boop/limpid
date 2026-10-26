import 'package:limpid_ai/src/budget/budget_guard.dart';
import 'package:limpid_ai/src/context/context_builder.dart';
import 'package:limpid_ai/src/context/token_estimator.dart';
import 'package:limpid_ai/src/model/ai_chunk.dart';
import 'package:limpid_ai/src/model/ai_error.dart';
import 'package:limpid_ai/src/model/ai_model_catalog.dart';
import 'package:limpid_ai/src/model/ai_options.dart';
import 'package:limpid_ai/src/model/ai_prompt.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_response.dart';
import 'package:limpid_ai/src/model/ai_task.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';
import 'package:limpid_ai/src/providers/llm_provider.dart';
import 'package:limpid_ai/src/rag/rag_index.dart';
import 'package:limpid_ai/src/tasks/ai_task_keys.dart';
import 'package:limpid_ai/src/tasks/ai_task_registry.dart';
import 'package:limpid_ai/src/tasks/prompt_renderer.dart';

/// Résolution de la fournisseur à utiliser pour un appel.
typedef AiProviderResolver =
    LlmProvider Function(AiProviderKind kind, {String? scope});

/// Façade de la passerelle IA.
///
/// Quatre points d'entrée :
/// - [generate] : appel complet à partir d'un prompt ;
/// - [stream] : appel en streaming, fragment par fragment ;
/// - [inline] : réécriture inline (étendre, raccourcir, simplifier, changer
///   le ton, traduire) ;
/// - [query] : interrogation du manuscrit (« interroge ton livre »).
///
/// Chaque appel peut être rattaché à un [BudgetGuard], qui plafonne la
/// consommation par requête et par jour.
class AiClient {
  /// Crée un client IA.
  AiClient({
    required AiProviderResolver providerResolver,
    AiTaskRegistry tasks = const AiTaskRegistry(),
    BudgetGuard? budgetGuard,
    ContextBuilder contextBuilder = const ContextBuilder(),
    RagIndex? ragIndex,
    AiEmbeddingProvider? embeddingProvider,
    TokenEstimator tokenEstimator = const HeuristicTokenEstimator(),
  }) : _providerResolver = providerResolver,
       _tasks = tasks,
       _budgetGuard = budgetGuard,
       _contextBuilder = contextBuilder,
       _ragIndex = ragIndex,
       _embeddingProvider = embeddingProvider,
       _tokenEstimator = tokenEstimator;

  /// Crée un client à partir d'une table de fournisseurs.
  ///
  /// Utile en test et pour une composition simple côté serveur.
  factory AiClient.withProviders(
    Map<AiProviderKind, LlmProvider> providers, {
    AiTaskRegistry tasks = const AiTaskRegistry(),
    BudgetGuard? budgetGuard,
    ContextBuilder contextBuilder = const ContextBuilder(),
    RagIndex? ragIndex,
    AiEmbeddingProvider? embeddingProvider,
    TokenEstimator tokenEstimator = const HeuristicTokenEstimator(),
  }) {
    return AiClient(
      providerResolver: (AiProviderKind kind, {String? scope}) {
        final LlmProvider? provider = providers[kind];
        if (provider == null) {
          throw const AiProviderError(
            code: 'ai_provider_unavailable',
            userMessage:
                "Ce fournisseur IA n'est pas configuré sur ce serveur.",
          );
        }
        return provider;
      },
      tasks: tasks,
      budgetGuard: budgetGuard,
      contextBuilder: contextBuilder,
      ragIndex: ragIndex,
      embeddingProvider: embeddingProvider,
      tokenEstimator: tokenEstimator,
    );
  }

  final AiProviderResolver _providerResolver;
  final AiTaskRegistry _tasks;
  final BudgetGuard? _budgetGuard;
  final ContextBuilder _contextBuilder;
  final RagIndex? _ragIndex;
  final AiEmbeddingProvider? _embeddingProvider;
  final TokenEstimator _tokenEstimator;

  /// Estimation de la sortie quand la tâche n'en fournit pas.
  static const int _defaultOutputEstimate = 800;

  /// Identifiant de repli pour un appel sans utilisateur identifié.
  static const String _anonymousUserId = 'anonymous';

  /// Registre des tâches disponibles.
  AiTaskRegistry get tasks => _tasks;

  /// Assembleur de contexte.
  ContextBuilder get contextBuilder => _contextBuilder;

  /// Exécute un appel complet.
  ///
  /// [task] fournit le modèle, le budget de sortie et la température par
  /// défaut ; [options] peut les surcharger.
  Future<AiResponse> generate(
    AiPrompt prompt, {
    AiProviderKind? provider,
    String? scope,
    AiTask? task,
    AiRequestOptions? options,
    AiCallTag? tag,
  }) async {
    final AiProviderKind kind =
        provider ?? task?.recommendedProvider ?? AiProviderKind.anthropic;
    final LlmProvider llm = _resolveProvider(kind, scope);
    final AiRequestOptions effective = _effectiveOptions(task, options, kind);

    await _authorize(prompt, task, effective, tag);
    final AiResponse response = await llm.complete(prompt, options: effective);
    await _record(response.usage, task, tag, kind);
    return response;
  }

  /// Exécute un appel en streaming.
  ///
  /// La consommation est enregistrée à la fin du flux, y compris si le flux
  /// est interrompu par une erreur.
  Stream<AiChunk> stream(
    AiPrompt prompt, {
    AiProviderKind? provider,
    String? scope,
    AiTask? task,
    AiRequestOptions? options,
    AiCallTag? tag,
  }) async* {
    final AiProviderKind kind =
        provider ?? task?.recommendedProvider ?? AiProviderKind.anthropic;
    final LlmProvider llm = _resolveProvider(kind, scope);
    final AiRequestOptions effective = _effectiveOptions(task, options, kind);

    await _authorize(prompt, task, effective, tag);

    AiUsage? usage;
    try {
      await for (final AiChunk chunk in llm.stream(
        prompt,
        options: effective,
      )) {
        if (chunk.usage != null) {
          usage = chunk.usage;
        }
        yield chunk;
      }
    } finally {
      if (usage != null) {
        await _record(usage, task, tag, kind);
      }
    }
  }

  /// Réécriture inline (fonctionnalité A1).
  Future<AiResponse> inline(
    AiInlineRequest request, {
    AiProviderKind? provider,
    String? scope,
    AiRequestOptions? options,
    AiCallTag? tag,
  }) async {
    final bool isTranslation = request.action == AiInlineAction.translate;
    final AiTask task = _tasks.require(
      isTranslation ? AiTaskKeys.translateText : AiTaskKeys.rewriteInline,
    );

    final Map<String, String> values = isTranslation
        ? <String, String>{
            'texte': request.text,
            'contexte': request.context ?? _noContext,
            'langue_cible': request.targetLanguage,
          }
        : <String, String>{
            'texte': request.text,
            'consigne': _inlineInstruction(request),
            'ton': request.tone ?? _originalTone,
            'contexte': request.context ?? _noContext,
          };

    final AiPrompt prompt = AiPrompt.systemAndUser(
      system: task.systemPrompt,
      user: PromptRenderer.renderUser(task, values),
    );

    return generate(
      prompt,
      provider: provider,
      scope: scope,
      task: task,
      options: options,
      tag: tag,
    );
  }

  /// Interroge le manuscrit (fonctionnalité A7).
  ///
  /// Les passages retenus sont issus de l'index RAG injecté. Lève
  /// [AiProviderError] si aucun index ou aucun embedder n'est configuré.
  Future<AiResponse> query(
    AiQueryRequest request, {
    AiProviderKind? provider,
    String? scope,
    AiRequestOptions? options,
    AiCallTag? tag,
  }) async {
    final RagIndex? index = _ragIndex;
    final AiEmbeddingProvider? embedder = _embeddingProvider;
    if (index == null || embedder == null) {
      throw const AiProviderError(
        code: 'ai_rag_unavailable',
        userMessage:
            "La recherche dans le manuscrit n'est pas disponible sur ce "
            'serveur.',
      );
    }

    final List<double> embedding = await embedder.embed(request.question);
    final List<RagSearchResult> results = await index.searchByEmbedding(
      embedding,
      limit: request.topK,
      minScore: request.minScore,
    );

    final AiTask task = _tasks.require(AiTaskKeys.queryBook);
    final AiPrompt prompt = AiPrompt.systemAndUser(
      system: task.systemPrompt,
      user: PromptRenderer.renderUser(task, <String, String>{
        'question': request.question,
        'passages': renderPassages(results),
      }),
    );

    return generate(
      prompt,
      provider: provider,
      scope: scope,
      task: task,
      options: options,
      tag: tag,
    );
  }

  /// Exécute une tâche du registre à partir de ses valeurs de modèle.
  Future<AiResponse> runTask(
    AiTask task,
    Map<String, String> values, {
    AiProviderKind? provider,
    String? scope,
    AiRequestOptions? options,
    AiCallTag? tag,
  }) async {
    final AiPrompt prompt = AiPrompt.systemAndUser(
      system: task.systemPrompt,
      user: PromptRenderer.renderUser(task, values),
    );
    return generate(
      prompt,
      provider: provider,
      scope: scope,
      task: task,
      options: options,
      tag: tag,
    );
  }

  /// Rend les passages RAG en texte exploitable par le modèle.
  static String renderPassages(List<RagSearchResult> results) {
    if (results.isEmpty) {
      return 'Aucun passage trouvé dans le manuscrit.';
    }
    final List<String> sections = <String>[
      for (final RagSearchResult result in results)
        '[${result.document.id}] (pertinence : '
            '${result.score.toStringAsFixed(2)})\n'
            '${result.document.text}',
    ];
    return sections.join('\n\n');
  }

  LlmProvider _resolveProvider(AiProviderKind kind, String? scope) {
    return _providerResolver(kind, scope: scope);
  }

  AiRequestOptions _effectiveOptions(
    AiTask? task,
    AiRequestOptions? options,
    AiProviderKind kind,
  ) {
    final AiRequestOptions base = options ?? const AiRequestOptions();
    return base.copyWith(
      model:
          base.model ??
          task?.recommendedModel ??
          AiModelCatalog.defaultModel(kind, AiModelTier.balanced),
      maxTokens: base.maxTokens ?? task?.maxTokens,
      temperature: base.temperature ?? task?.temperature,
    );
  }

  Future<void> _authorize(
    AiPrompt prompt,
    AiTask? task,
    AiRequestOptions options,
    AiCallTag? tag,
  ) async {
    final BudgetGuard? guard = _budgetGuard;
    if (guard == null) {
      return;
    }
    final int inputEstimate = _tokenEstimator.estimate(prompt.plainText);
    final int outputEstimate =
        task?.estimatedOutputTokens ??
        options.maxTokens ??
        _defaultOutputEstimate;

    await guard.authorize(
      estimatedInputTokens: inputEstimate,
      estimatedOutputTokens: outputEstimate,
      userId: tag?.userId ?? _anonymousUserId,
      feature: tag?.feature ?? task?.key ?? 'ai_generate',
      taskKey: task?.key,
      model: options.model,
    );
  }

  Future<void> _record(
    AiUsage usage,
    AiTask? task,
    AiCallTag? tag,
    AiProviderKind kind,
  ) async {
    final BudgetGuard? guard = _budgetGuard;
    if (guard == null) {
      return;
    }
    await guard.record(
      usage,
      userId: tag?.userId ?? _anonymousUserId,
      feature: tag?.feature ?? task?.key ?? 'ai_generate',
      taskKey: task?.key,
      provider: kind,
    );
  }

  String _inlineInstruction(AiInlineRequest request) {
    final String? extra = request.instruction;
    if (extra == null || extra.trim().isEmpty) {
      return request.action.instruction;
    }
    return '${request.action.instruction} Contrainte supplémentaire : $extra.';
  }

  static const String _noContext = 'Aucun contexte narratif n\'est fourni.';

  static const String _originalTone = 'le ton d\'origine, sans le modifier';
}
