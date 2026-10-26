import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart' hide AiInlineRequest, AiQueryRequest;

import '../errors/app_exception.dart';
import 'ai_gateway.dart';

/// The [AiGateway] backed by the multi-provider gateway of `limpid_ai`.
///
/// Anthropic Claude is the default provider; the key comes from the
/// environment and never reaches the logs.
final class LimpidAiGateway implements AiGateway {
  /// Creates a gateway on top of [client].
  const LimpidAiGateway({required this.client});

  /// The underlying AI client.
  final AiClient client;

  /// Builds a gateway talking to Anthropic with [apiKey].
  factory LimpidAiGateway.anthropic({
    required String apiKey,
    http.Client? httpClient,
  }) {
    final InMemoryCredentialStore credentials = InMemoryCredentialStore();
    credentials.store(AiProviderKind.anthropic, apiKey);
    final AnthropicProvider provider = AnthropicProvider(
      httpClient: httpClient ?? http.Client(),
      credentialStore: credentials,
    );
    return LimpidAiGateway(
      client: AiClient.withProviders(<AiProviderKind, LlmProvider>{
        AiProviderKind.anthropic: provider,
      }),
    );
  }

  @override
  Stream<AiEvent> generate(AiGenerateRequest request) {
    final AiTask? task = request.taskKey == null
        ? null
        : client.tasks.find(request.taskKey!);
    final AiPrompt prompt = request.system == null
        ? AiPrompt.user(request.prompt)
        : AiPrompt.systemAndUser(system: request.system!, user: request.prompt);
    final AiRequestOptions options = AiRequestOptions(
      maxTokens: request.maxTokens,
      temperature: request.temperature,
    );
    return _guard(
      client
          .stream(
            prompt,
            task: task,
            options: options,
            tag: AiCallTag(
              feature: request.taskKey ?? 'ai_generate',
              userId: request.userId,
            ),
          )
          .map(_toEvent),
    );
  }

  @override
  Stream<AiEvent> inline(AiInlineRequest request) {
    final bool isTranslation = request.action == 'translate';
    final AiTask task = client.tasks.require(
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
            'consigne': _instruction(request),
            'ton': request.tone ?? _originalTone,
            'contexte': request.context ?? _noContext,
          };

    final AiPrompt prompt = AiPrompt.systemAndUser(
      system: task.systemPrompt,
      user: PromptRenderer.renderUser(task, values),
    );

    return _guard(
      client
          .stream(
            prompt,
            task: task,
            options: AiRequestOptions(maxTokens: request.maxTokens),
            tag: AiCallTag(
              feature: 'ai_inline',
              userId: request.userId,
              taskKey: task.key,
            ),
          )
          .map(_toEvent),
    );
  }

  @override
  Stream<AiEvent> query(AiQueryRequest request) {
    return _guard(_streamQuery(request));
  }

  Stream<AiEvent> _streamQuery(AiQueryRequest request) async* {
    const HashingEmbeddingProvider embedder = HashingEmbeddingProvider();
    final InMemoryVectorIndex index = InMemoryVectorIndex(
      embeddingProvider: embedder,
    );
    for (final ManuscriptSource source in request.sources) {
      await index.upsert(
        RagDocument(
          id: source.id,
          text: source.text,
          embedding: await embedder.embed(source.text),
        ),
      );
    }

    final List<double> embedding = await embedder.embed(request.question);
    final List<RagSearchResult> results = await index.searchByEmbedding(
      embedding,
      limit: request.topK,
      minScore: 0.05,
    );

    final AiTask task = client.tasks.require(AiTaskKeys.queryBook);
    final AiPrompt prompt = AiPrompt.systemAndUser(
      system: task.systemPrompt,
      user: PromptRenderer.renderUser(task, <String, String>{
        'question': request.question,
        'passages': AiClient.renderPassages(results),
      }),
    );

    await for (final AiEvent event
        in client
            .stream(
              prompt,
              task: task,
              tag: AiCallTag(
                feature: 'ai_query',
                userId: request.userId,
                taskKey: task.key,
              ),
            )
            .map(_toEvent)) {
      yield event;
    }
  }

  static AiEvent _toEvent(AiChunk chunk) {
    if (chunk.isDone) {
      final AiUsage usage = chunk.usage ?? AiUsage.empty();
      return AiDoneEvent(
        text: chunk.text,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        estimatedCostUsd: usage.estimatedCostUsd,
      );
    }
    return AiTokenEvent(chunk.text);
  }

  static Stream<AiEvent> _guard(Stream<AiEvent> events) async* {
    try {
      yield* events;
    } on AiError catch (error) {
      throw AiProviderUnavailableException(
        message: error.userMessage,
        details: <String, Object?>{'provider': error.providerName},
        cause: error,
      );
    } on AiProviderUnavailableException {
      rethrow;
    } on Object catch (error) {
      throw AiProviderUnavailableException(
        message: 'Le service IA est momentanément indisponible.',
        cause: error,
      );
    }
  }

  static String _instruction(AiInlineRequest request) {
    final String? extra = request.instruction;
    if (extra == null || extra.trim().isEmpty) {
      return AiInlineAction.values
          .firstWhere(
            (AiInlineAction action) => action.name == request.action,
            orElse: () => AiInlineAction.expand,
          )
          .instruction;
    }
    return '${AiInlineAction.values.firstWhere((AiInlineAction action) => action.name == request.action, orElse: () => AiInlineAction.expand).instruction} Contrainte supplémentaire : $extra.';
  }

  static const String _noContext = 'Aucun contexte narratif n\'est fourni.';

  static const String _originalTone = 'le ton d\'origine, sans le modifier';
}
