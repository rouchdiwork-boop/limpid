import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../middleware/rate_limiter.dart';
import '../services/stripe_webhook_service.dart';

/// Le nombre de livraisons qu'un appelant peut envoyer en rafale.
///
/// Le webhook est public : la signature prouve l'origine de la livraison,
/// elle ne dit rien du débit. La route a donc son propre seau, plus serré
/// que celui de l'API.
const int stripeWebhookRateLimitCapacity = 60;

/// Le nombre de livraisons qu'un appelant regagne par seconde.
const double stripeWebhookRateLimitRefillPerSecond = 2;

/// Enregistre la route du webhook Stripe.
///
/// La route ne demande aucun jeton de session : elle s'authentifie par la
/// signature que Stripe appose sur chaque livraison, comme l'API publique
/// s'authentifie par sa clé. Elle est donc hors du chemin des routes
/// authentifiées, et le point de composition doit ajouter
/// `/v1/stripe/webhook` aux chemins exempts du jeton de session — le
/// contrôle du second facteur ne s'applique alors pas non plus.
///
/// Le rate limiter général s'applique comme sur les autres routes ; la
/// route a en plus son propre seau.
void registerStripeWebhookRoutes(
  Router router,
  StripeWebhookService service,
  AppConfig config,
) {
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: stripeWebhookRateLimitCapacity,
    refillPerSecond: stripeWebhookRateLimitRefillPerSecond,
  );

  router.post(
    '/v1/stripe/webhook',
    rateLimitMiddleware(
      limiter: limiter,
      scope: 'stripe_webhook',
      applies: (Request request) => true,
    )((Request request) => _receive(request, service, config)),
  );
}

/// Reçoit une livraison Stripe et rend l'issue de son traitement.
Future<Response> _receive(
  Request request,
  StripeWebhookService service,
  AppConfig config,
) async {
  // Le corps est lu une seule fois et vérifié tel quel : le
  // re-sérialiser changerait la signature, et Stripe ne retient que le
  // corps qu'il a envoyé.
  final List<int> payload = await _readBody(request, config.maxBodyBytes);
  final StripeWebhookResult result = await service.handle(
    payload: payload,
    signature: request.headers['stripe-signature'],
    ip: clientIpOf(request),
  );
  return ApiResponse.ok(<String, Object?>{
    'event_id': result.eventId,
    'event_type': result.eventType,
    'outcome': result.outcome.key,
  });
}

/// Le corps de la requête, borné par [maxBytes].
///
/// Le corps est lu comme une suite d'octets, jamais comme du texte : la
/// signature porte sur les octets exacts reçus, et un corps qui n'est pas
/// de l'UTF-8 valide doit être refusé, pas réécrit.
Future<List<int>> _readBody(Request request, int maxBytes) async {
  final int? length = request.contentLength;
  if (length != null && length > maxBytes) {
    throw PayloadTooLargeException(
      limitBytes: maxBytes,
      message: 'Le corps de la requête dépasse la taille maximale autorisée.',
    );
  }
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request.read()) {
    builder.add(chunk);
    // La longueur annoncée peut mentir : c'est le corps lu qui fait foi,
    // et il ne doit jamais grossir au-delà de la limite.
    if (builder.length > maxBytes) {
      throw PayloadTooLargeException(
        limitBytes: maxBytes,
        message: 'Le corps de la requête dépasse la taille maximale autorisée.',
      );
    }
  }
  return builder.takeBytes();
}
