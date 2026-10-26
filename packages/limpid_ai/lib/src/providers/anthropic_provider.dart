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

/// Fournisseur Anthropic (Claude) via l'API Messages.
class AnthropicProvider extends HttpLlmProvider {
  /// Crée un fournisseur Anthropic.
  AnthropicProvider({
    required super.httpClient,
    required super.credentialStore,
    super.timeout,
    this.baseUrl = 'https://api.anthropic.com',
    this.apiVersion = '2023-06-01',
    this.scope,
    this.defaultMaxTokens = 4096,
  });

  /// Racine de l'API Anthropic.
  final String baseUrl;

  /// Version de l'API sent dans l'en-tête `anthropic-version`.
  final String apiVersion;

  /// Périmètre de la clé (permet plusieurs comptes).
  final String? scope;

  /// Plafond de tokens de sortie utilisé quand l'appel n'en précise aucun.
  final int defaultMaxTokens;

  @override
  AiProviderKind get kind => AiProviderKind.anthropic;

  @override
  Uri endpoint() => Uri.parse('$_trimmedBaseUrl$apiVersion/messages');

  String get _trimmedBaseUrl {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  @override
  Future<Map<String, String>> authHeaders() async {
    final String? apiKey = await credentialStore.read(
      AiProviderKind.anthropic,
      scope: scope,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw AiProviderError(
        code: 'ai_missing_credentials',
        userMessage: "Aucune clé d'API Anthropic n'est configurée.",
        providerName: kind.wireName,
      );
    }
    return <String, String>{
      'x-api-key': apiKey,
      'anthropic-version': apiVersion,
    };
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
          AiProviderKind.anthropic,
          AiModelTier.balanced,
        ),
      ),
      'max_tokens': options.maxTokens ?? defaultMaxTokens,
      'messages': conversation
          .map((AiMessage message) => message.toJson())
          .toList(growable: false),
      'stream': stream,
    };

    final String system = prompt.systemText;
    if (system.isNotEmpty) {
      body['system'] = system;
    }
    if (!options.omitTemperature && options.temperature != null) {
      body['temperature'] = options.temperature;
    }
    return body;
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
    final Map<String, String> headers = await _headers(options);
    final http.StreamedResponse streamed = await sendJson(
      url: endpoint(),
      headers: headers,
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
    final Map<String, String> headers = await _headers(options);
    final http.StreamedResponse streamed = await sendJson(
      url: endpoint(),
      headers: headers,
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

    await for (final SseEvent event in SseDecoder.decode(
      decodeLines(streamed),
    )) {
      final Map<String, dynamic> data = ProviderJson.asObject(
        event.data,
        providerName: kind.wireName,
      );
      final String type = ProviderJson.asString(
        data['type'],
        fallback: event.event ?? '',
      );

      switch (type) {
        case 'message_start':
          usage = _mergeUsage(usage, _usageFromMessageStart(data));
          break;
        case 'content_block_delta':
          final String text = _textDelta(data);
          if (text.isNotEmpty) {
            yield AiChunk(text: text, model: requestedModel);
          }
          break;
        case 'message_delta':
          final String? stopReason = _stopReason(data);
          if (stopReason == 'refusal') {
            throw AiSafetyRefusal(providerName: kind.wireName);
          }
          usage = _mergeUsage(usage, _usageFromMessageDelta(data));
          break;
        case 'error':
          throw _streamError(data);
        case 'content_block_stop':
        case 'message_stop':
        case 'ping':
          break;
        default:
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
    final String? stopReason =
        ProviderJson.asString(json['stop_reason']).isEmpty
        ? null
        : ProviderJson.asString(json['stop_reason']);
    if (stopReason == 'refusal') {
      throw AiSafetyRefusal(providerName: kind.wireName);
    }

    final StringBuffer buffer = StringBuffer();
    for (final Object? block in ProviderJson.asList(json['content'])) {
      if (block is Map<String, dynamic> &&
          ProviderJson.asString(block['type']) == 'text') {
        buffer.write(ProviderJson.asString(block['text']));
      }
    }

    final Map<String, dynamic> usageJson = _usageObject(json['usage']);
    final int inputTokens = ProviderJson.asInt(usageJson['input_tokens']);
    final int outputTokens = ProviderJson.asInt(usageJson['output_tokens']);
    final String model = ProviderJson.asString(
      json['model'],
      fallback: requestedModel,
    );

    return AiResponse(
      text: buffer.toString(),
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
      stopReason: stopReason,
    );
  }

  Map<String, dynamic> _usageObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const <String, dynamic>{};
  }

  AiUsage _usageFromMessageStart(Map<String, dynamic> data) {
    final Object? message = data['message'];
    if (message is! Map<String, dynamic>) {
      return const AiUsage.empty();
    }
    return _usageFromRaw(_usageObject(message['usage']));
  }

  AiUsage _usageFromMessageDelta(Map<String, dynamic> data) {
    return _usageFromRaw(_usageObject(data['usage']));
  }

  AiUsage _usageFromRaw(Map<String, dynamic> raw) {
    return AiUsage(
      inputTokens: ProviderJson.asInt(raw['input_tokens']),
      outputTokens: ProviderJson.asInt(raw['output_tokens']),
    );
  }

  AiUsage _mergeUsage(AiUsage current, AiUsage incoming) {
    return current.copyWith(
      inputTokens: incoming.inputTokens == 0
          ? current.inputTokens
          : incoming.inputTokens,
      outputTokens: incoming.outputTokens == 0
          ? current.outputTokens
          : incoming.outputTokens,
    );
  }

  String _textDelta(Map<String, dynamic> data) {
    final Object? delta = data['delta'];
    if (delta is! Map<String, dynamic>) {
      return '';
    }
    if (ProviderJson.asString(delta['type']) != 'text_delta') {
      return '';
    }
    return ProviderJson.asString(delta['text']);
  }

  String? _stopReason(Map<String, dynamic> data) {
    final Object? delta = data['delta'];
    if (delta is! Map<String, dynamic>) {
      return null;
    }
    final String reason = ProviderJson.asString(delta['stop_reason']);
    return reason.isEmpty ? null : reason;
  }

  AiError _streamError(Map<String, dynamic> data) {
    final Object? error = data['error'];
    final Map<String, dynamic> errorJson = error is Map<String, dynamic>
        ? error
        : const <String, dynamic>{};
    final String type = ProviderJson.asString(errorJson['type']);
    final String message = ProviderJson.asString(errorJson['message']);
    final Map<String, String> details = <String, String>{
      if (type.isNotEmpty) 'provider_error_type': type,
      if (message.isNotEmpty) 'provider_message': message,
    };

    if (type == 'rate_limit_error' || type == 'overloaded_error') {
      return AiRateLimited(providerName: kind.wireName, details: details);
    }
    return AiProviderError(
      code: 'ai_provider_error',
      userMessage: 'Le service IA a interrompu la génération.',
      providerName: kind.wireName,
      details: details,
    );
  }
}
