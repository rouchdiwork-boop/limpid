import 'package:http/http.dart' as http;
import 'package:limpid_ai/src/model/ai_chunk.dart';
import 'package:limpid_ai/src/model/ai_error.dart';
import 'package:limpid_ai/src/model/ai_message.dart';
import 'package:limpid_ai/src/model/ai_model_catalog.dart';
import 'package:limpid_ai/src/model/ai_options.dart';
import 'package:limpid_ai/src/model/ai_prompt.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_response.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';
import 'package:limpid_ai/src/providers/http_provider_base.dart';
import 'package:limpid_ai/src/providers/provider_json.dart';
import 'package:limpid_ai/src/providers/sse_decoder.dart';

/// Fournisseur compatible OpenAI.
///
/// Couvre OpenAI, Groq, Together, DeepSeek, LM Studio et Ollama exposé via
/// `/v1`. Seule l'URL de base change d'un fournisseur à l'autre.
class OpenAiCompatibleProvider extends HttpLlmProvider {
  /// Crée un fournisseur compatible OpenAI.
  OpenAiCompatibleProvider({
    required super.httpClient,
    required super.credentialStore,
    super.timeout,
    this.baseUrl = 'https://api.openai.com/v1',
    this.scope,
    this.defaultMaxTokens = 4096,
    this.includeStreamOptions = true,
    this.requiresApiKey = true,
  });

  /// Racine de l'API, terminateur `/v1` inclus.
  final String baseUrl;

  /// Périmètre de la clé (par exemple `groq`, `together`).
  final String? scope;

  /// Plafond de tokens de sortie utilisé quand l'appel n'en précise aucun.
  final int defaultMaxTokens;

  /// Demande les statistiques d'usage dans le flux (certaines passerelles
  /// locales ne le supportent pas).
  final bool includeStreamOptions;

  /// Indique si une clé d'API est nécessaire.
  final bool requiresApiKey;

  @override
  AiProviderKind get kind => AiProviderKind.openaiCompatible;

  @override
  Uri endpoint() => Uri.parse('$_trimmedBaseUrl/chat/completions');

  String get _trimmedBaseUrl {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  @override
  Future<Map<String, String>> authHeaders() async {
    if (!requiresApiKey) {
      return const <String, String>{};
    }
    final String? apiKey = await credentialStore.read(
      AiProviderKind.openaiCompatible,
      scope: scope,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw AiProviderError(
        code: 'ai_missing_credentials',
        userMessage: "Aucune clé d'API n'est configurée pour ce service IA.",
        providerName: kind.wireName,
      );
    }
    return <String, String>{'authorization': 'Bearer $apiKey'};
  }

  @override
  Map<String, dynamic> buildRequestBody(
    AiPrompt prompt,
    AiRequestOptions options, {
    required bool stream,
  }) {
    final List<AiMessage> conversation = requireConversation(prompt);
    final Map<String, dynamic> body = <String, dynamic>{
      'model': effectiveModel(
        options,
        AiModelCatalog.defaultModel(
          AiProviderKind.openaiCompatible,
          AiModelTier.balanced,
        ),
      ),
      'max_tokens': options.maxTokens ?? defaultMaxTokens,
      'messages': _wireMessages(prompt, conversation),
      'stream': stream,
    };

    if (!options.omitTemperature && options.temperature != null) {
      body['temperature'] = options.temperature;
    }
    if (stream && includeStreamOptions) {
      body['stream_options'] = <String, dynamic>{'include_usage': true};
    }
    return body;
  }

  List<Map<String, String>> _wireMessages(
    AiPrompt prompt,
    List<AiMessage> conversation,
  ) {
    final List<Map<String, String>> messages = <Map<String, String>>[];
    final String system = prompt.systemText;
    if (system.isNotEmpty) {
      messages.add(<String, String>{
        'role': AiRole.system.wireName,
        'content': system,
      });
    }
    for (final AiMessage message in conversation) {
      messages.add(message.toJson());
    }
    return messages;
  }

  @override
  Future<AiResponse> complete(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async {
    final Map<String, dynamic> body = buildRequestBody(
      prompt,
      options,
      stream: false,
    );
    final http.StreamedResponse streamed = await sendJson(
      url: endpoint(),
      headers: await _headers(options),
      body: body,
    );
    final String rawBody = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw mapHttpError(
        http.Response(rawBody, streamed.statusCode, headers: streamed.headers),
      );
    }
    return _parseResponse(rawBody, requestedModel: body['model'] as String);
  }

  @override
  Stream<AiChunk> stream(
    AiPrompt prompt, {
    AiRequestOptions options = const AiRequestOptions(),
  }) async* {
    final Map<String, dynamic> body = buildRequestBody(
      prompt,
      options,
      stream: true,
    );
    final http.StreamedResponse streamed = await sendJson(
      url: endpoint(),
      headers: await _headers(options),
      body: body,
    );

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final String rawBody = await streamed.stream.bytesToString();
      throw mapHttpError(
        http.Response(rawBody, streamed.statusCode, headers: streamed.headers),
      );
    }

    final String requestedModel = body['model'] as String;
    final StringBuffer buffer = StringBuffer();
    AiUsage usage = const AiUsage.empty();

    await for (final SseEvent event in SseDecoder.decode(
      decodeLines(streamed),
    )) {
      if (event.data.trim() == _doneMarker) {
        break;
      }
      final Map<String, dynamic> data = ProviderJson.asObject(
        event.data,
        providerName: kind.wireName,
      );

      final Map<String, dynamic> usageJson = _usageObject(data['usage']);
      if (usageJson.isNotEmpty) {
        usage = usage.copyWith(
          inputTokens: ProviderJson.asInt(
            usageJson['prompt_tokens'],
            fallback: usage.inputTokens,
          ),
          outputTokens: ProviderJson.asInt(
            usageJson['completion_tokens'],
            fallback: usage.outputTokens,
          ),
        );
      }

      final List<Object?> choices = ProviderJson.asList(data['choices']);
      if (choices.isEmpty) {
        continue;
      }
      final Object? choice = choices.first;
      if (choice is! Map<String, dynamic>) {
        continue;
      }
      final String finishReason = ProviderJson.asString(
        choice['finish_reason'],
      );
      if (finishReason == 'content_filter') {
        throw AiSafetyRefusal(providerName: kind.wireName);
      }
      final Object? delta = choice['delta'];
      if (delta is Map<String, dynamic>) {
        final String text = ProviderJson.asString(delta['content']);
        if (text.isNotEmpty) {
          buffer.write(text);
          yield AiChunk(text: text, model: requestedModel);
        }
      }
    }

    yield AiChunk.done(
      usage: usage.copyWith(
        estimatedCostUsd: estimateCost(
          requestedModel,
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens,
        ),
      ),
      model: requestedModel,
    );
  }

  Future<Map<String, String>> _headers(AiRequestOptions options) async {
    return <String, String>{
      ...await authHeaders(),
      ...providerHeaders(),
      ...options.extraHeaders,
    };
  }

  AiResponse _parseResponse(String rawBody, {required String requestedModel}) {
    final Map<String, dynamic> json = ProviderJson.asObject(
      rawBody,
      providerName: kind.wireName,
    );
    final List<Object?> choices = ProviderJson.asList(json['choices']);
    if (choices.isEmpty) {
      throw AiInvalidResponse(
        providerName: kind.wireName,
        details: <String, String>{'reason': 'aucun choix renvoyé'},
      );
    }
    final Object? choice = choices.first;
    if (choice is! Map<String, dynamic>) {
      throw AiInvalidResponse(
        providerName: kind.wireName,
        details: <String, String>{'reason': 'choix illisible'},
      );
    }

    final String finishReason = ProviderJson.asString(choice['finish_reason']);
    if (finishReason == 'content_filter') {
      throw AiSafetyRefusal(providerName: kind.wireName);
    }

    final Object? message = choice['message'];
    final String text = message is Map<String, dynamic>
        ? ProviderJson.asString(message['content'])
        : '';

    final Map<String, dynamic> usageJson = _usageObject(json['usage']);
    final int inputTokens = ProviderJson.asInt(usageJson['prompt_tokens']);
    final int outputTokens = ProviderJson.asInt(usageJson['completion_tokens']);
    final String model = ProviderJson.asString(
      json['model'],
      fallback: requestedModel,
    );

    return AiResponse(
      text: text,
      usage: AiUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        estimatedCostUsd: estimateCost(
          model,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
        ),
      ),
      model: model,
      provider: kind,
      stopReason: finishReason.isEmpty ? null : finishReason,
    );
  }

  Map<String, dynamic> _usageObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const <String, dynamic>{};
  }

  static const String _doneMarker = '[DONE]';
}
