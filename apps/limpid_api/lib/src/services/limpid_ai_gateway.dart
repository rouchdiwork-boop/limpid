import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart' hide AiInlineRequest, AiQueryRequest;

import '../errors/app_exception.dart';
import 'ai_consent_service.dart';
import 'ai_gateway.dart';

/// The [AiGateway] backed by the multi-provider gateway of `limpid_ai`.
///
/// Anthropic Claude is the default provider; the key comes from the
/// environment and never reaches the logs.
final class LimpidAiGateway implements AiGateway {
  /// Creates a gateway on top of [client].
  ///
  /// [consents] porte le consentement de l'auteur : sans lui, la passerelle
  /// refuse tout appel, car elle ne peut pas dire si le texte de l'auteur a
  /// le droit de partir chez un tiers (D-08).
  const LimpidAiGateway({
    required this.client,
    this.estimator = const HeuristicTokenEstimator(),
    this.consents,
    this.provider = 'anthropic',
  });

  /// The underlying AI client.
  final AiClient client;

  /// The estimator of the tokens, used when the provider does not report
  /// its own consumption.
  ///
  /// The estimate is then marked as an estimate: a count that pretends to
  /// be exact ends up in the invoice of an author.
  final TokenEstimator estimator;

  /// Le service du consentement de l'auteur, `null` quand il n'est pas
  /// configuré.
  ///
  /// Une passerelle sans ce service ne demande rien à personne, et refuse
  /// donc tout appel : mieux vaut un assistant indisponible qu'un texte
  /// parti sans l'accord de son auteur.
  final AiConsentService? consents;

  /// Le fournisseur que la passerelle interroge vraiment.
  ///
  /// C'est ce nom que la garde du consentement regarde : la decision de
  /// l'auteur porte sur le fournisseur qui recoit son texte, pas sur celui
  /// que le service de consentement croit configure. Les deux doivent
  /// dire la meme chose.
  final String provider;

  /// Builds a gateway talking to Anthropic with [apiKey].
  factory LimpidAiGateway.anthropic({
    required String apiKey,
    AiConsentService? consents,
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
      consents: consents,
    );
  }

  /// Vérifie que l'auteur a autorisé l'envoi de son texte.
  ///
  /// La vérification est **avant** l'appel : elle lève une exception, et ni
  /// la fournisseur n'est appelée ni le flux ouvert.
  @override
  Future<void> ensureConsent({required String userId}) async {
    final AiConsentService? service = consents;
    if (service == null) {
      throw const ServiceUnavailableException(
        message:
            "Le contrôle du consentement à l'IA n'est pas configuré sur ce "
            "poste : l'assistant est indisponible.",
      );
    }
    await service.ensureAllowed(userId: userId, provider: provider);
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
      _events(
        client.stream(
          prompt,
          task: task,
          options: options,
          tag: AiCallTag(
            feature: request.taskKey ?? 'ai_generate',
            userId: request.userId,
          ),
        ),
        estimatedInputTokens: estimator.estimate(prompt.plainText),
      ),
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
      _events(
        client.stream(
          prompt,
          task: task,
          options: AiRequestOptions(maxTokens: request.maxTokens),
          tag: AiCallTag(
            feature: 'ai_inline',
            userId: request.userId,
            taskKey: task.key,
          ),
        ),
        estimatedInputTokens: estimator.estimate(prompt.plainText),
      ),
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

    await for (final AiEvent event in _events(
      client.stream(
        prompt,
        task: task,
        tag: AiCallTag(
          feature: 'ai_query',
          userId: request.userId,
          taskKey: task.key,
        ),
      ),
      estimatedInputTokens: estimator.estimate(prompt.plainText),
    )) {
      yield event;
    }
  }

  /// Transforms the fragments of the provider into the events of the API.
  ///
  /// The text is accumulated along the stream: the final event carries the
  /// complete text, and it is what allows the output to be estimated when
  /// the provider does not say how many tokens it wrote.
  Stream<AiEvent> _events(
    Stream<AiChunk> chunks, {
    required int estimatedInputTokens,
  }) async* {
    final StringBuffer text = StringBuffer();
    await for (final AiChunk chunk in chunks) {
      if (chunk.isDone) {
        if (chunk.text.isNotEmpty) text.write(chunk.text);
        yield _doneEvent(
          chunk,
          text: text.toString(),
          estimatedInputTokens: estimatedInputTokens,
        );
        continue;
      }
      text.write(chunk.text);
      yield AiTokenEvent(chunk.text);
    }
  }

  /// The final event, with the consumption of the call.
  ///
  /// When the provider reported its own consumption, the count is exact.
  /// Otherwise it is estimated, and marked as an estimate: an estimate
  /// that pretends to be a reading ends up in the invoice of an author.
  AiEvent _doneEvent(
    AiChunk chunk, {
    required String text,
    required int estimatedInputTokens,
  }) {
    final AiUsage? usage = chunk.usage;
    if (usage != null && usage.totalTokens > 0) {
      return AiDoneEvent(
        text: text,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        estimatedCostUsd: usage.estimatedCostUsd,
        isTokenCountEstimated: false,
      );
    }
    return AiDoneEvent(
      text: text,
      inputTokens: estimatedInputTokens,
      outputTokens: estimator.estimate(text),
      estimatedCostUsd: 0,
      isTokenCountEstimated: true,
    );
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
