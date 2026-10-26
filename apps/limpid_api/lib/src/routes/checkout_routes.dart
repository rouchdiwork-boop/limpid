import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/idempotency_service.dart';
import '../services/payment_gateway.dart';

/// The number of checkout sessions a single caller may open in a burst.
const int checkoutRateLimitCapacity = 5;

/// How many checkout sessions a single caller regains per second.
const double checkoutRateLimitRefillPerSecond = 0.2;

/// Registers the routes of the checkout.
void registerCheckoutRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  // L'ouverture d'une session de paiement touche le prestataire de paiement :
  // elle est limitée par le même mécanisme que les autres écritures, avec un
  // seau propre au checkout.
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: checkoutRateLimitCapacity,
    refillPerSecond: checkoutRateLimitRefillPerSecond,
  );

  router.post(
    '/v1/checkout',
    rateLimitMiddleware(
      limiter: limiter,
      scope: 'checkout',
      applies: (Request request) => true,
    )((Request request) => _createCheckout(request, dependencies, config)),
  );

  router.get('/v1/checkout/<sessionId>', (
    Request request,
    String sessionId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final CheckoutSession? session = await dependencies.payments
        .retrieveSession(sessionId);
    // La session appartient à son créateur : une session d'un autre compte est
    // introuvable, et la réponse ne confirme jamais qu'elle existe.
    if (session == null || session.ownerId != auth.userId) {
      throw const NotFoundException(
        message: "Cette session de paiement n'existe pas.",
      );
    }
    return ApiResponse.ok(session.toJson());
  });
}

Future<Response> _createCheckout(
  Request request,
  AppDependencies dependencies,
  AppConfig config,
) async {
  final AuthContext auth = requireAuthContext(request);

  // Le corps est borné par la même limite que les autres routes : un client
  // authentifié ne peut pas faire charger un corps arbitrairement grand en
  // mémoire.
  final JsonBody body = await JsonBody.fromRequest(
    request,
    maxBytes: config.maxBodyBytes,
  );
  final String fingerprint = body.canonicalJson;

  final String? rawKey = request.headers['idempotency-key'];
  final String? trimmedKey = rawKey?.trim();
  final String? idempotencyKey = (trimmedKey == null || trimmedKey.isEmpty)
      ? null
      : trimmedKey;

  if (idempotencyKey != null) {
    final IdempotencyOutcome outcome = await dependencies.idempotency.begin(
      ownerId: auth.userId,
      key: idempotencyKey,
      body: fingerprint,
    );
    if (outcome.status == IdempotencyStatus.replay) {
      final String? stored = outcome.storedResponse;
      if (stored != null) return ApiResponse.raw(stored);
    }
  }

  final String plan = body.requireString('plan');
  final String successUrl = body.requireString('success_url');
  final String cancelUrl = body.requireString('cancel_url');

  final CheckoutSession session = await dependencies.payments.createSession(
    CheckoutRequest(
      userId: auth.userId,
      plan: plan,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
      idempotencyKey: idempotencyKey,
    ),
  );

  await dependencies.audit.record(
    AuditEntry(
      userId: auth.userId,
      action: 'plan.checkout_started',
      targetType: 'subscription',
      targetId: session.id,
      metadata: <String, Object?>{'plan': plan},
      ip: clientIpOf(request),
    ),
  );

  final String encoded = ApiResponse.encode(<String, Object?>{
    'data': session.toJson(),
  });
  if (idempotencyKey != null) {
    await dependencies.idempotency.complete(
      ownerId: auth.userId,
      key: idempotencyKey,
      body: fingerprint,
      response: encoded,
    );
  }

  return ApiResponse.raw(encoded);
}
