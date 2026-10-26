import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_ai/src/model/ai_error.dart';
import 'package:limpid_ai/src/model/ai_message.dart';
import 'package:limpid_ai/src/model/ai_options.dart';
import 'package:limpid_ai/src/model/ai_pricing.dart';
import 'package:limpid_ai/src/model/ai_prompt.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/credential_store.dart';
import 'package:limpid_ai/src/providers/llm_provider.dart';
import 'package:limpid_ai/src/providers/provider_json.dart';

/// Base commune des fournisseursalking HTTP.
///
/// Centralise l'envoi des requêtes, la gestion du délai d'attente, le
/// décodage du corps et la traduction des codes HTTP en erreurs typées.
abstract class HttpLlmProvider implements LlmProvider {
  /// Crée une fournisseur HTTP.
  HttpLlmProvider({
    required this.httpClient,
    required this.credentialStore,
    this.timeout = const Duration(seconds: 120),
  });

  /// Client HTTP injecté (transport interchangeable, testable sans réseau).
  final http.Client httpClient;

  /// Source des clés d'API.
  final AiCredentialStore credentialStore;

  /// Délai maximal d'attente des en-têtes de réponse.
  final Duration timeout;

  /// URL de l'endpoint appelé.
  Uri endpoint();

  /// Corps JSON de la requête.
  Map<String, dynamic> buildRequestBody(
    AiPrompt prompt,
    AiRequestOptions options, {
    required bool stream,
  });

  /// En-têtes spécifiques à la fournisseur (hors authentification).
  Map<String, String> providerHeaders() => const <String, String>{};

  /// En-têtes d'authentification.
  ///
  /// Renvoie une table vide lorsque la fournisseur n'exige aucune clé
  /// (cas d'Ollama en mode local).
  Future<Map<String, String>> authHeaders() async => const <String, String>{};

  /// Messages de la conversation, en refusant une requête sans message
  /// utilisateur.
  List<AiMessage> requireConversation(AiPrompt prompt) {
    final List<AiMessage> messages = prompt.conversationMessages;
    if (messages.isEmpty) {
      throw AiProviderError(
        code: 'ai_invalid_request',
        userMessage: 'La demande IA ne contient aucun message utilisateur.',
        providerName: kind.wireName,
      );
    }
    return messages;
  }

  /// Envoie la requête et renvoie la réponse brute (headers + flux de corps).
  Future<http.StreamedResponse> sendJson({
    required Uri url,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final http.Request request = http.Request('POST', url)
      ..headers.addAll(<String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        ...headers,
      })
      ..body = jsonEncode(body);

    try {
      return await httpClient.send(request).timeout(timeout);
    } on TimeoutException {
      throw AiTimeout(providerName: kind.wireName, timeout: timeout);
    } on http.ClientException catch (error) {
      throw AiProviderError(
        code: 'ai_provider_error',
        userMessage:
            'Le service IA est injoignable. Vérifiez la connexion réseau.',
        providerName: kind.wireName,
        details: <String, String>{'reason': error.message},
      );
    }
  }

  /// Lit le corps d'une réponse en streaming et le convertit en lignes.
  Stream<String> decodeLines(http.StreamedResponse response) {
    return response.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());
  }

  /// Traduit une réponse HTTP en erreur typée.
  AiError mapHttpError(http.Response response) {
    final int status = response.statusCode;
    final String? providerMessage = ProviderJson.extractErrorMessage(
      response.body,
    );
    final Map<String, String> details = <String, String>{
      if (providerMessage != null) 'provider_message': providerMessage,
    };

    if (status == 429 || status == 529) {
      return AiRateLimited(
        providerName: kind.wireName,
        statusCode: status,
        details: details,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (status == 401 || status == 403) {
      return AiProviderError(
        code: 'ai_auth_error',
        userMessage:
            'Les identifiants du service IA sont invalides ou ont expiré.',
        providerName: kind.wireName,
        statusCode: status,
        details: details,
      );
    }
    if (status == 408 || status == 504) {
      return AiTimeout(
        providerName: kind.wireName,
        statusCode: status,
        details: details,
      );
    }
    return AiProviderError(
      code: 'ai_provider_error',
      userMessage: 'Le service IA a renvoyé une erreur. Réessayez.',
      providerName: kind.wireName,
      statusCode: status,
      details: details,
    );
  }

  /// Convertit un en-tête `retry-after` (secondes) en durée.
  static Duration? parseRetryAfter(String? headerValue) {
    if (headerValue == null) {
      return null;
    }
    final int? seconds = int.tryParse(headerValue.trim());
    if (seconds == null) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  /// Coût estimé d'un appel, à partir du modèle et des volumes de tokens.
  double estimateCost(
    String model, {
    required int inputTokens,
    required int outputTokens,
  }) {
    return AiPricing.estimateCostUsd(
      model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }

  /// Modèle effectif de l'appel (option prioritaire sur le modèle par
  /// défaut de la fournisseur).
  String effectiveModel(AiRequestOptions options, String fallbackModel) {
    final String? model = options.model;
    if (model == null || model.isEmpty) {
      return fallbackModel;
    }
    return model;
  }

  /// Identifiant de la fournisseur, exposé pour les sous-classes.
  @override
  AiProviderKind get kind;
}
