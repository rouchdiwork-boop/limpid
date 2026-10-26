import 'package:http/http.dart' as http;
import 'package:limpid_ai/src/model/ai_chunk.dart';
import 'package:limpid_ai/src/model/ai_message.dart';
import 'package:limpid_ai/src/model/ai_model_catalog.dart';
import 'package:limpid_ai/src/model/ai_options.dart';
import 'package:limpid_ai/src/model/ai_prompt.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_response.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';
import 'package:limpid_ai/src/providers/http_provider_base.dart';
import 'package:limpid_ai/src/providers/provider_json.dart';

/// Fournisseur Ollama en mode local.
///
/// Utilise l'API native `/api/chat`. Le flux renvoyé par Ollama est du
/// JSON délimité par des retours à la ligne (et non du SSE) : chaque ligne
/// est un objet JSON indépendant.
class OllamaProvider extends HttpLlmProvider {
  /// Crée un fournisseur Ollama local.
  OllamaProvider({
    required super.httpClient,
    required super.credentialStore,
    super.timeout,
    this.baseUrl = 'http://localhost:11434',
    this.defaultMaxTokens = 4096,
  });

  /// Racine de l'API Ollama.
  final String baseUrl;

  /// Plafond de tokens de sortie utilisé quand l'appel n'en précise aucun.
  final int defaultMaxTokens;

  @override
  AiProviderKind get kind => AiProviderKind.ollama;

  @override
  Uri endpoint() => Uri.parse('$_trimmedBaseUrl/api/chat');

  String get _trimmedBaseUrl {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  @override
  Map<String, dynamic> buildRequestBody(
    AiPrompt prompt,
    AiRequestOptions options, {
    required bool stream,
  }) {
    final List<AiMessage> conversation = requireConversation(prompt);
    final Map<String, dynamic> optionsBody = <String, dynamic>{
      'num_predict': options.maxTokens ?? defaultMaxTokens,
    };
    if (!options.omitTemperature && options.temperature != null) {
      optionsBody['temperature'] = options.temperature;
    }

    return <String, dynamic>{
      'model': effectiveModel(
        options,
        AiModelCatalog.defaultModel(
          AiProviderKind.ollama,
          AiModelTier.balanced,
        ),
      ),
      'messages': _wireMessages(prompt, conversation),
      'stream': stream,
      'options': optionsBody,
    };
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
    AiUsage usage = const AiUsage.empty();

    await for (final String line in decodeLines(streamed)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final Map<String, dynamic> data = ProviderJson.asObject(
        line,
        providerName: kind.wireName,
      );

      final Object? message = data['message'];
      if (message is Map<String, dynamic>) {
        final String text = ProviderJson.asString(message['content']);
        if (text.isNotEmpty) {
          yield AiChunk(text: text, model: requestedModel);
        }
      }

      if (data['done'] == true) {
        usage = usage.copyWith(
          inputTokens: ProviderJson.asInt(
            data['prompt_eval_count'],
            fallback: usage.inputTokens,
          ),
          outputTokens: ProviderJson.asInt(
            data['eval_count'],
            fallback: usage.outputTokens,
          ),
        );
        break;
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
    final Object? message = json['message'];
    final String text = message is Map<String, dynamic>
        ? ProviderJson.asString(message['content'])
        : '';

    final int inputTokens = ProviderJson.asInt(json['prompt_eval_count']);
    final int outputTokens = ProviderJson.asInt(json['eval_count']);
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
      stopReason: json['done'] == true ? 'stop' : null,
    );
  }
}
