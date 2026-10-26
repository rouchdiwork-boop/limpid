import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart';

import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import '../logging/logger.dart';
import 'api_access_guard.dart';
import 'webhook_service.dart';
import 'webhook_url_policy.dart';

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

/// Le nombre maximal de points de rappel servis pour un evenement.
///
/// Un compte ne peut pas transformer le service en relais : chaque point
/// ajoute une attente de [defaultWebhookTimeout] a l'envoi.
const int maxWebhookEndpointsPerEvent = 50;

/// Le temps total accorde a l'envoi d'un evenement a tous ses points.
///
/// Le budget est partage : passe, les points restants ne sont pas servis
/// et l'echec est journalise.
const Duration webhookFanOutBudget = Duration(seconds: 30);

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
    this.logger,
    this.allowPrivateHosts = false,
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

  /// Le journal du serveur, `null` quand le dispatcher est sans journal.
  ///
  /// Il ne reçoit que des identifiants : ni la charge livrée, ni le secret
  /// du point de rappel, ni le texte du livre.
  final Logger? logger;

  /// Whether the callback may live on a private host.
  ///
  /// It is true only in the development profile, where the author tests a
  /// delivery against a local callback. In production, a callback that
  /// resolves to the deployment's own network is refused.
  final bool allowPrivateHosts;

  final http.Client _client;
  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// Le temps de réponse accordé au point de rappel.
  final Duration timeout;

  /// Émet l'événement [event] vers les points de rappel du compte [userId].
  ///
  /// L'émission part en arrière-plan et ne lève jamais : l'opération qui a
  /// produit l'événement ne doit pas échouer parce que la livraison a
  /// échoué. Un export qui a réussi reste réussi quand l'URL du rappel est
  /// morte.
  ///
  /// La charge est nettoyée avant de partir : ni secret, ni texte de livre,
  /// ni donnée d'un autre compte.
  void emit({
    required String userId,
    required WebhookEvent event,
    required Map<String, Object?> data,
  }) {
    unawaited(_emit(userId, event, data));
  }

  /// Livre l'événement et encaisse son échec.
  ///
  /// Le journal des livraisons porte la trace de chaque tentative : une
  /// livraison qui échoue y laisse son statut et son motif. Le journal du
  /// serveur garde, lui, la trace de l'incident.
  Future<void> _emit(
    String userId,
    WebhookEvent event,
    Map<String, Object?> data,
  ) async {
    final Map<String, Object?> payload = sanitizeWebhookData(data);
    if (payload.length != data.length) {
      logger?.warning('webhook.payload.filtered', <String, Object?>{
        'event': event.key,
        'dropped': data.length - payload.length,
      });
    }
    try {
      final List<WebhookDeliveryRecord> deliveries = await dispatch(
        userId: userId,
        event: event,
        data: payload,
      );
      for (final WebhookDeliveryRecord delivery in deliveries) {
        if (!delivery.isFailed) continue;
        logger?.warning('webhook.delivery.failed', <String, Object?>{
          'event': event.key,
          'delivery_id': delivery.id,
          'endpoint_id': delivery.endpointId,
          'http_status': delivery.httpStatus,
        });
      }
    } on Object catch (error) {
      // La livraison a échoué : l'opération qui l'a déclenchée reste
      // réussie. L'incident est journalisé, il ne remonte pas à l'appelant.
      logger?.warning('webhook.dispatch.failed', <String, Object?>{
        'event': event.key,
        'error': error.toString(),
      });
    }
  }

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
    final DateTime deadline = _clock().add(webhookFanOutBudget);
    for (final WebhookEndpointRecord endpoint in endpoints) {
      // L'eventail est borne : un compte ne peut pas noyer le service, ni
      // lui faire ecrire des heures apres l'evenement.
      if (deliveries.length >= maxWebhookEndpointsPerEvent) {
        logger?.warning('webhook.dispatch.truncated', <String, Object?>{
          'event': event.key,
          'reason': 'too_many_endpoints',
          'limit': maxWebhookEndpointsPerEvent,
        });
        break;
      }
      if (!_clock().isBefore(deadline)) {
        logger?.warning('webhook.dispatch.truncated', <String, Object?>{
          'event': event.key,
          'reason': 'budget_exceeded',
        });
        break;
      }
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
    // Le rejeu respecte le meme invariant que l'envoi : un compte qui a
    // quitté la formule Studio ne rejoue pas ses livraisons.
    final ApiAccessGuard? accessGuard = guard;
    if (accessGuard != null && !await accessGuard.canAccess(userId)) {
      throw const ForbiddenException(
        message:
            "L'API publique et les webhooks sont réservés à la formule "
            'Studio.',
        details: <String, Object?>{'feature': 'api_and_webhooks'},
      );
    }

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

    final Uri target = Uri.parse(endpoint.url);

    // Le nom est resolu au moment de l'ecrire : un domaine public peut
    // designer une adresse interne (`127.0.0.1.nip.io`), et un
    // enregistrement peut changer entre la declaration et la livraison.
    if (!allowPrivateHosts) {
      final HostResolution resolution = await resolveHost(target.host);
      if (resolution != HostResolution.public) {
        return delivery.copyWith(
          status: WebhookDeliveryStatus.failed,
          errorMessage: switch (resolution) {
            HostResolution.privateAddress =>
              'Le point de rappel se resout vers une adresse interne : '
                  'la livraison est refusee.',
            HostResolution.unresolved =>
              'Le point de rappel ne se resout pas : la livraison est '
                  'refusee.',
            HostResolution.public => null,
          },
          attempts: attempts,
          completedAt: _now(),
        );
      }
    }

    try {
      // Les redirections ne sont **jamais** suivies : la politique d'URL
      // verifie l'hote que l'auteur a declare, pas celui vers lequel son
      // serveur nous renverrait. Un `303` transformerait la livraison en
      // une lecture vers une adresse interne, depuis le reseau du deploiement.
      final http.Request request = http.Request('POST', target)
        ..headers.addAll(headers)
        ..body = payload
        ..followRedirects = false;
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(timeout);
      final http.Response response = await http.Response.fromStream(streamed);
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

/// Les champs qu'une charge de webhook ne porte jamais.
///
/// Le texte du livre n'a rien à faire dans une notification : il sort de
/// l'application chez un tiers, et il ne se rattrapera pas.
const Set<String> forbiddenWebhookFields = <String>{
  'body',
  'content',
  'payload',
  'prompt',
  'text',
};

/// Les marqueurs d'un champ secret, quel que soit le nom qu'il porte.
///
/// Un champ dont le nom **contient** l'un de ces marqueurs est retiré :
/// `refresh_token` est aussi secret que `token`.
const List<String> webhookSecretMarkers = <String>[
  'apikey',
  'authorization',
  'credential',
  'cookie',
  'jwt',
  'passwd',
  'password',
  'privatekey',
  'secret',
  'token',
];

/// Nettoie la charge [data] des champs qu'un webhook ne doit pas porter.
///
/// La charge part chez un tiers : elle ne peut ni révéler un secret, ni
/// transporter le texte du livre, ni exposer la donnée d'un autre compte.
/// Le champ retiré est une faute de l'émetteur : il disparaît de la
/// charge, et l'émetteur est prié de le signaler.
///
/// Le nettoyage descend dans les cartes et les listes : un secret caché
/// sous une clé innocente (`meta`, `details`) est aussi un secret.
Map<String, Object?> sanitizeWebhookData(Map<String, Object?> data) {
  final Map<String, Object?> safe = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in data.entries) {
    final String key = entry.key.toLowerCase();
    if (forbiddenWebhookFields.contains(key) || _carriesSecret(key)) continue;
    safe[entry.key] = _sanitizeValue(entry.value);
  }
  return safe;
}

/// Nettoie la valeur [value] avant qu'elle ne parte chez un tiers.
///
/// Une carte est nettoyée comme la charge elle-même, une liste est
/// nettoyée élément par élément, tout le reste passe tel quel.
Object? _sanitizeValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> nested = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) continue;
      nested[key] = _sanitizeValue(entry.value);
    }
    return sanitizeWebhookData(nested);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_sanitizeValue));
  }
  return value;
}

/// Le nom du champ [key] porte-t-il un marqueur de secret ?
bool _carriesSecret(String key) {
  final String normalized = key.replaceAll(RegExp(r'[_\-.]'), '');
  for (final String marker in webhookSecretMarkers) {
    if (normalized.contains(marker)) return true;
  }
  return false;
}
