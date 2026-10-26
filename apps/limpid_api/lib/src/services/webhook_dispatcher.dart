import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart';

import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import 'api_access_guard.dart';
import 'webhook_service.dart';

/// L'en-tête qui porte la signature de la charge livrée.
const String webhookSignatureHeader = 'X-Limpid-Signature';

/// L'en-tête qui porte la signature de l'ancien secret, pendant la période
/// de transition qui suit une rotation.
const String webhookPreviousSignatureHeader = 'X-Limpid-Signature-Previous';

/// L'en-tête qui porte le nom technique de l'événement livré.
const String webhookEventHeader = 'X-Limpid-Event';

/// L'en-tête qui porte l'identifiant de la livraison.
const String webhookDeliveryHeader = 'X-Limpid-Delivery';

/// Le temps de réponse accordé au point de rappel.
const Duration defaultWebhookTimeout = Duration(seconds: 10);

/// Le dispatcher des webhooks sortants.
///
/// Le dispatcher envoie la charge JSON de l'événement aux points de rappel
/// abonnés, la signe avec le secret du point, et consigne chaque tentative
/// dans le journal des livraisons.
final class WebhookDispatcher {
  /// Crée un dispatcher sur le port [database].
  WebhookDispatcher({
    required this.database,
    this.guard,
    http.Client? client,
    UlidGenerator? generator,
    DateTime Function()? clock,
    this.timeout = defaultWebhookTimeout,
  }) : _client = client ?? http.Client(),
       _generator = generator ?? UlidGenerator(),
       _clock = clock ?? DateTime.now;

  /// Le port de persistance des points de rappel et des livraisons.
  final WebhookDatabase database;

  /// Le garde-fou de la formule, quand il est câblé.
  ///
  /// Un compte qui a quitté la formule Studio cesse de recevoir ses
  /// livraisons : ses points de rappel ne sont plus alimentés.
  final ApiAccessGuard? guard;
  final http.Client _client;
  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// Le temps de réponse accordé au point de rappel.
  final Duration timeout;

  /// Envoie l'événement [event] aux points de rappel du compte [userId].
  ///
  /// Chaque tentative est consignée, qu'elle aboutisse ou non : le journal
  /// des livraisons est la preuve de ce que le serveur a envoyé. Un point de
  /// rappel qui échoue n'empêche pas les autres de recevoir l'événement.
  Future<List<WebhookDeliveryRecord>> dispatch({
    required String userId,
    required WebhookEvent event,
    required Map<String, Object?> data,
  }) async {
    final ApiAccessGuard? accessGuard = guard;
    if (accessGuard != null && !await accessGuard.canAccess(userId)) {
      return const <WebhookDeliveryRecord>[];
    }
    final List<WebhookEndpointRecord> endpoints = await database
        .listSubscribedEndpoints(userId: userId, event: event.key);
    final List<WebhookDeliveryRecord> deliveries = <WebhookDeliveryRecord>[];
    for (final WebhookEndpointRecord endpoint in endpoints) {
      deliveries.add(await _deliver(endpoint, event, data));
    }
    return List<WebhookDeliveryRecord>.unmodifiable(deliveries);
  }

  /// Rejoue la livraison [deliveryId] du compte [userId].
  ///
  /// Le rejeu renvoie la charge telle qu'elle a été préparée, vers l'URL
  /// que le compte a déclarée pour le point de rappel. L'URL d'un rejeu
  /// n'est jamais prise dans la requête : le compte ne peut donc pas
  /// faire partir une livraison vers une adresse qu'il n'a pas déclarée.
  Future<WebhookDeliveryRecord> replay({
    required String userId,
    required String deliveryId,
  }) async {
    final WebhookDeliveryRecord? delivery = await database.findDelivery(
      deliveryId,
    );
    if (delivery == null || delivery.userId != userId) {
      throw const NotFoundException(message: "Cette livraison n'existe pas.");
    }
    if (!delivery.isFailed) {
      throw const ConflictException(
        message:
            'Cette livraison a déjà abouti : elle ne peut pas être rejouée.',
      );
    }

    final WebhookEndpointRecord? endpoint = await database.findEndpoint(
      delivery.endpointId,
    );
    if (endpoint == null || endpoint.userId != userId) {
      throw const NotFoundException(
        message:
            'Le point de rappel de cette livraison n\'existe plus : la '
            'livraison ne peut pas être rejouée.',
      );
    }
    if (!endpoint.isActive) {
      throw const ConflictException(
        message:
            'Ce point de rappel est désactivé : la livraison ne peut pas '
            'être rejouée.',
      );
    }

    final WebhookDeliveryRecord replayed = await _send(
      endpoint: endpoint,
      delivery: delivery,
      event: WebhookEvent.parse(delivery.event) ?? WebhookEvent.exportCompleted,
      payload: delivery.payload,
      attempts: delivery.attempts + 1,
    );
    await database.updateDelivery(replayed);
    return replayed;
  }

  /// Prépare et envoie une livraison vers le point de rappel [endpoint].
  Future<WebhookDeliveryRecord> _deliver(
    WebhookEndpointRecord endpoint,
    WebhookEvent event,
    Map<String, Object?> data,
  ) async {
    final String deliveryId = _generator.generate().value;
    final DateTime now = _now();
    final String payload = jsonEncode(<String, Object?>{
      'id': deliveryId,
      'type': event.key,
      'created_at': now.toIso8601String(),
      'data': data,
    });
    final WebhookDeliveryRecord delivery = WebhookDeliveryRecord(
      id: deliveryId,
      endpointId: endpoint.id,
      userId: endpoint.userId,
      event: event.key,
      payload: payload,
      status: WebhookDeliveryStatus.pending,
      attempts: 1,
      createdAt: now,
    );
    await database.insertDelivery(delivery);
    final WebhookDeliveryRecord sent = await _send(
      endpoint: endpoint,
      delivery: delivery,
      event: event,
      payload: payload,
      attempts: 1,
    );
    await database.updateDelivery(sent);
    return sent;
  }

  /// Envoie la charge [payload] au point de rappel [endpoint].
  ///
  /// La charge est signée avec le secret courant du point. Pendant la
  /// période de transition qui suit une rotation, l'ancienne signature
  /// accompagne la nouvelle : le destinataire accepte l'une ou l'autre.
  Future<WebhookDeliveryRecord> _send({
    required WebhookEndpointRecord endpoint,
    required WebhookDeliveryRecord delivery,
    required WebhookEvent event,
    required String payload,
    required int attempts,
  }) async {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'user-agent': 'Limpid-Webhooks/1.0',
      webhookSignatureHeader: signWebhookPayload(endpoint.secret, payload),
      webhookEventHeader: event.key,
      webhookDeliveryHeader: delivery.id,
    };
    if (endpoint.isPreviousSecretValid(_now())) {
      final String? previous = endpoint.previousSecret;
      if (previous != null) {
        headers[webhookPreviousSignatureHeader] = signWebhookPayload(
          previous,
          payload,
        );
      }
    }

    try {
      final http.Response response = await _client
          .post(Uri.parse(endpoint.url), headers: headers, body: payload)
          .timeout(timeout);
      final bool succeeded =
          response.statusCode >= 200 && response.statusCode < 300;
      return delivery.copyWith(
        status: succeeded
            ? WebhookDeliveryStatus.succeeded
            : WebhookDeliveryStatus.failed,
        httpStatus: response.statusCode,
        errorMessage: succeeded ? null : _reasonOf(response.statusCode),
        attempts: attempts,
        completedAt: _now(),
      );
    } on TimeoutException {
      return delivery.copyWith(
        status: WebhookDeliveryStatus.failed,
        errorMessage: 'Le point de rappel n\'a pas répondu à temps.',
        attempts: attempts,
        completedAt: _now(),
      );
    } on http.ClientException catch (error) {
      return delivery.copyWith(
        status: WebhookDeliveryStatus.failed,
        errorMessage: 'Le point de rappel est injoignable : ${error.message}.',
        attempts: attempts,
        completedAt: _now(),
      );
    } on FormatException {
      return delivery.copyWith(
        status: WebhookDeliveryStatus.failed,
        errorMessage: 'L\'URL du point de rappel est invalide.',
        attempts: attempts,
        completedAt: _now(),
      );
    }
  }

  /// Le motif consigné quand le point de rappel refuse la livraison.
  static String _reasonOf(int status) {
    return 'Le point de rappel a répondu avec le code $status.';
  }

  DateTime _now() => _clock().toUtc();
}

/// Signe la charge [payload] avec le secret [secret].
///
/// La signature est un HMAC-SHA256 de la charge, présenté sous la forme
/// `sha256=<hexadécimal>`.
String signWebhookPayload(String secret, String payload) {
  final Hmac hmac = Hmac(sha256, utf8.encode(secret));
  return 'sha256=${hmac.convert(utf8.encode(payload))}';
}
