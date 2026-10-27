import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/book_sale_store.dart';
import '../db/entitlement_store.dart';
import '../db/promo_code_store.dart';
import '../db/quota_database.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/book_sale_service.dart';
import '../services/idempotency_service.dart';
import '../services/payment_gateway.dart';
import '../services/redirect_url_policy.dart';

/// Le nombre de sessions de paiement qu'un appelant peut ouvrir d'un coup.
const int checkoutRateLimitCapacity = 5;

/// Le nombre de sessions de paiement qu'un appelant récupère par seconde.
const double checkoutRateLimitRefillPerSecond = 0.2;

/// L'action journalée quand un acheteur commande un livre.
const String bookCheckoutStartedAction = 'book.checkout_started';

/// Enregistre les routes de la commande.
///
/// La commande d'un abonnement et la commande d'un livre sont deux routes
/// voisines : l'une achète une formule, l'autre achète un livre. Elles
/// partagent le seau de limite, parce qu'elles touchent toutes les deux le
/// prestataire de paiement.
///
/// La commande d'un livre n'existe que quand les magasins de la vente sont
/// câblés : un serveur qui ne vend pas de livre ne sert pas la route,
/// plutôt que de la servir en erreur.
void registerCheckoutRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  BookSaleStore? sales,
  EntitlementStore? entitlements,
  PromoCodeStore? promoCodes,
}) {
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

  if (sales == null || entitlements == null || promoCodes == null) return;
  final BookSaleService books = BookSaleService(
    sales: sales,
    entitlements: entitlements,
    promoCodes: promoCodes,
    projects: dependencies.projects,
    storage: dependencies.storage,
    audit: dependencies.audit,
  );
  router.post(
    '/v1/checkout/book',
    rateLimitMiddleware(
      limiter: limiter,
      scope: 'checkout',
      applies: (Request request) => true,
    )((Request request) async {
      return _createBookCheckout(request, dependencies, config, books);
    }),
  );
}

/// La commande d'un livre.
///
/// Le corps porte le livre et, éventuellement, un code promo. Le **prix**
/// n'en fait pas partie : il est lu dans la base, et un corps qui en
/// porterait un serait ignoré.
///
/// La commande est idempotente : la clé `Idempotency-Key` rejoue la
/// première réponse, comme pour l'abonnement.
Future<Response> _createBookCheckout(
  Request request,
  AppDependencies dependencies,
  AppConfig config,
  BookSaleService books,
) async {
  final AuthContext auth = requireAuthContext(request);

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

  final String projectId = body.requireString('project_id');
  final String? promoCode = body.optionalString('promo_code');
  // L'adresse de retour n'est pas choisie par l'appelant : elle doit
  // viser une origine de la plateforme, sinon le prestataire renverrait
  // l'acheteur vers un site tiers.
  final String successUrl = validateRedirectUrl(
    body.requireString('success_url'),
    allowedOrigins: config.allowedOrigins,
  );
  final String cancelUrl = validateRedirectUrl(
    body.requireString('cancel_url'),
    allowedOrigins: config.allowedOrigins,
  );

  final BookPaymentGateway? gateway = bookGatewayOf(dependencies.payments);
  if (gateway == null) {
    throw const ServiceUnavailableException(
      message:
          'Le prestataire de paiement ne vend pas de livre sur ce poste : '
          'la commande est indisponible.',
    );
  }

  final BookOrder order = await books.order(
    buyerId: auth.userId,
    projectId: projectId,
    successUrl: successUrl,
    cancelUrl: cancelUrl,
    gateway: gateway,
    promoCode: promoCode,
    idempotencyKey: idempotencyKey,
  );

  await dependencies.audit.record(
    AuditEntry(
      userId: auth.userId,
      action: bookCheckoutStartedAction,
      targetType: 'book_sale',
      targetId: projectId,
      metadata: <String, Object?>{
        'amount_cents': order.amountInCents,
        'currency': order.currency,
        'discount_cents': order.discountInCents,
        'promo_code': ?order.promoCode,
        'is_free': order.isFree,
      },
      ip: clientIpOf(request),
    ),
  );

  final String encoded = ApiResponse.encode(<String, Object?>{
    'data': order.toJson(),
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

  final String planKey = body.requireString('plan');
  final BillingPeriod? period = _readPeriod(body);
  // L'adresse de retour n'est pas choisie par l'appelant : elle doit
  // viser une origine de la plateforme, sinon le prestataire renverrait
  // l'acheteur vers un site tiers.
  final String successUrl = validateRedirectUrl(
    body.requireString('success_url'),
    allowedOrigins: config.allowedOrigins,
  );
  final String cancelUrl = validateRedirectUrl(
    body.requireString('cancel_url'),
    allowedOrigins: config.allowedOrigins,
  );

  // La commande est résolue avant d'atteindre le prestataire de paiement :
  // une formule qui n'existe pas, la formule gratuite ou un cycle que la
  // formule ne propose pas sont refusés ici, et le champ fautif est nommé.
  final SubscriptionOrder order = SubscriptionOrder.resolve(
    planKey: planKey,
    period: period,
  );

  // L'essai gratuit s'accorde **une fois** par compte (D-15). La commande
  // le decide en lisant l'historique du compte : un compte qui a deja
  // consomme son essai ne recoit pas de periode d'essai a la seconde.
  final bool startTrial = await _mayStartTrial(dependencies, auth.userId);

  final CheckoutSession session = await dependencies.payments.createSession(
    CheckoutRequest(
      userId: auth.userId,
      plan: order.plan,
      period: order.period,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
      idempotencyKey: idempotencyKey,
      startTrial: startTrial,
    ),
  );

  await dependencies.audit.record(
    AuditEntry(
      userId: auth.userId,
      action: 'plan.checkout_started',
      targetType: 'subscription',
      targetId: session.id,
      metadata: <String, Object?>{
        'plan': order.plan.name,
        'period': order.period.name,
      },
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

/// Le cycle de facturation demandé par le client, `null` quand il n'en
/// demande aucun.
///
/// Le cycle est facultatif : un client qui le porte dans le nom de la
/// formule (`studio_yearly`) reste compris. Un cycle inconnu est refusé, et
/// le champ fautif est nommé.
BillingPeriod? _readPeriod(JsonBody body) {
  final String? raw = body.optionalString('period');
  if (raw == null) return null;
  for (final BillingPeriod period in BillingPeriod.values) {
    if (period.name == raw) return period;
  }
  throw ValidationException(
    field: 'period',
    message:
        'Le champ « period » doit valoir '
        '${BillingPeriod.values.map((BillingPeriod value) => value.name).join(' ou ')}.',
    details: <String, Object?>{'field': 'period'},
  );
}

/// Le compte peut-il encore beneficier d'un essai gratuit ?
///
/// La reponse est **fermee par defaut** : sans base des formules, aucun
/// essai n'est offert. Un compte qui a deja consomme son essai n'en
/// beneficie pas une seconde fois.
Future<bool> _mayStartTrial(AppDependencies dependencies, String userId) async {
  final QuotaDatabase? quotas = dependencies.quotas;
  if (quotas == null) return false;
  final AccountPlan? plan = await quotas.planOf(userId);
  if (plan == null) return false;
  return !plan.hasConsumedTrial;
}
