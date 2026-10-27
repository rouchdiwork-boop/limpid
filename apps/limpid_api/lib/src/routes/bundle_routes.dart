import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/book_sale_store.dart';
import '../db/bundle_record.dart';
import '../db/entitlement_store.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/promo_code_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/book_sale_service.dart';
import '../services/bundle_service.dart';
import '../services/idempotency_service.dart';
import '../services/payment_gateway.dart';
import '../services/redirect_url_policy.dart';

/// L'action journalée quand un auteur crée un bundle.
const String bundleCreatedAction = 'bundle.created';

/// L'action journalée quand un auteur met son bundle en vente.
const String bundlePublishedAction = 'bundle.published';

/// L'action journalée quand un acheteur commande un bundle.
const String bundleCheckoutStartedAction = 'bundle.checkout_started';

/// Le nombre de prix publics qu'une adresse IP peut demander d'un coup.
const int publicBundleRateLimitCapacity = 60;

/// Le nombre de prix publics qu'une adresse IP regagne par seconde.
const double publicBundleRateLimitRefillPerSecond = 2;

/// Le nombre de sessions de paiement qu'un appelant peut ouvrir d'un coup.
const int bundleCheckoutRateLimitCapacity = 5;

/// Le nombre de sessions de paiement qu'un appelant récupère par seconde.
const double bundleCheckoutRateLimitRefillPerSecond = 0.2;

/// Enregistre les routes des bundles.
///
/// Les routes décrivent le cycle du bundle : l'auteur crée son ensemble,
/// le met en vente, le lecteur le regarde et l'achète. Elles s'adressent au
/// compte authentifié, et lisent le compte dans le contexte authentifié —
/// jamais dans le corps de la requête.
///
/// Le magasin est exigé : un serveur qui ne vend pas de bundle ne sert pas
/// ces routes, plutôt que de les servir en erreur.
void registerBundleRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  required BundleStore bundles,
  required BookSaleStore sales,
  required EntitlementStore entitlements,
  required PromoCodeStore promoCodes,
}) {
  // La base des projets : la vitrine publique ne montre que les livres
  // que leur auteur a publies.
  final ProjectStore projects = dependencies.projects;
  final BookSaleService books = BookSaleService(
    sales: sales,
    entitlements: entitlements,
    promoCodes: promoCodes,
    projects: dependencies.projects,
    storage: dependencies.storage,
    audit: dependencies.audit,
  );
  final BundleService service = BundleService(
    bundles: bundles,
    books: books,
    audit: dependencies.audit,
  );

  // -------------------------------------------------------------------
  // La création du bundle, par le vendeur.
  // -------------------------------------------------------------------

  router.post('/v1/bundles', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final List<String> projectIds = _readProjectIds(body);
    final BundleRecord bundle = await service.create(
      ownerId: auth.userId,
      title: body.requireString('title', maxLength: 200),
      description: body.optionalString('description', maxLength: 2000) ?? '',
      projectIds: projectIds,
      priceInCents: body.requireInt('price_cents', min: 0),
      currency: body.optionalString('currency') ?? 'eur',
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: bundleCreatedAction,
        targetType: 'bundle',
        targetId: bundle.id,
        metadata: <String, Object?>{
          'price_cents': bundle.priceInCents,
          'currency': bundle.currency,
          'project_ids': List<String>.unmodifiable(bundle.projectIds),
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(bundle.toJson(), status: HttpStatus.created);
  });

  // -------------------------------------------------------------------
  // La mise en vente, par le vendeur.
  // -------------------------------------------------------------------

  router.put('/v1/bundles/<bundleId>/publication', (
    Request request,
    String bundleId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final bool isPublished = body.requireBool('is_published');
    final BundleRecord bundle = await service.publish(
      ownerId: auth.userId,
      bundleId: bundleId,
      isPublished: isPublished,
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: bundlePublishedAction,
        targetType: 'bundle',
        targetId: bundle.id,
        metadata: <String, Object?>{
          'is_published': bundle.isPublished,
          'price_cents': bundle.priceInCents,
          'currency': bundle.currency,
          'project_ids': List<String>.unmodifiable(bundle.projectIds),
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(bundle.toJson());
  });

  // -------------------------------------------------------------------
  // La lecture du bundle.
  // -------------------------------------------------------------------

  router.get('/v1/bundles', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final List<BundleRecord> owned = await service.bundlesOf(auth.userId);
    final List<Map<String, Object?>> bundles = <Map<String, Object?>>[];
    for (final BundleRecord bundle in owned) {
      bundles.add(await _bundleJson(bundle, sales, isPublic: false));
    }
    return ApiResponse.ok(bundles);
  });

  router.get('/v1/bundles/<bundleId>', (
    Request request,
    String bundleId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final BundleRecord? bundle = await service.bundleOf(bundleId);
    if (bundle == null) {
      throw const NotFoundException(message: "Ce bundle n'existe pas.");
    }
    if (bundle.ownerId == auth.userId) {
      return ApiResponse.ok(await _bundleJson(bundle, sales, isPublic: false));
    }
    if (!bundle.isPublished) {
      // Un bundle en préparation n'existe que pour son vendeur : la réponse
      // ne dit pas à un tiers que le bundle existe.
      throw const NotFoundException(message: "Ce bundle n'existe pas.");
    }
    return ApiResponse.ok(
      await _bundleJson(bundle, sales, isPublic: true, projects: projects),
    );
  });

  // Le prix est public : la page du bundle se regarde sans compte, et le
  // lecteur n'en fait un que pour acheter. La route répond sous le
  // préfixe public de la vitrine — elle est donc exemptée du jeton — et
  // elle est limitée comme elle.
  final TokenBucketRateLimiter publicBundleLimiter = TokenBucketRateLimiter(
    capacity: publicBundleRateLimitCapacity,
    refillPerSecond: publicBundleRateLimitRefillPerSecond,
  );

  router.get('/v1/public/bundles/<bundleId>', (
    Request request,
    String bundleId,
  ) {
    return rateLimitMiddleware(
      limiter: publicBundleLimiter,
      scope: 'public_bundle',
      applies: (Request request) => true,
    )((Request request) async {
      final BundleRecord? bundle = await service.bundleOf(bundleId);
      if (bundle == null || !bundle.isPublished) {
        // Un bundle inconnu, un bundle qui n'est pas en vente et un bundle
        // en préparation répondent la même chose : le visiteur ne doit pas
        // apprendre qu'un bundle existe.
        throw const NotFoundException(message: "Ce bundle n'est pas en vente.");
      }
      return ApiResponse.ok(
        await _bundleJson(bundle, sales, isPublic: true, projects: projects),
      );
    })(request);
  });

  // -------------------------------------------------------------------
  // La commande du bundle, en paiement unique.
  // -------------------------------------------------------------------

  final TokenBucketRateLimiter checkoutLimiter = TokenBucketRateLimiter(
    capacity: bundleCheckoutRateLimitCapacity,
    refillPerSecond: bundleCheckoutRateLimitRefillPerSecond,
  );

  router.post(
    '/v1/checkout/bundle',
    rateLimitMiddleware(
      limiter: checkoutLimiter,
      scope: 'bundle_checkout',
      applies: (Request request) => true,
    )((Request request) async {
      return _createBundleCheckout(request, dependencies, config, service);
    }),
  );
}

/// La commande d'un bundle.
///
/// Le corps porte le bundle et, éventuellement, un code promo. Le **prix**
/// n'en fait pas partie : il est lu dans la base, et un corps qui en
/// porterait un serait ignoré.
///
/// La commande est idempotente : la clé `Idempotency-Key` rejoue la
/// première réponse, comme pour l'achat d'un livre.
Future<Response> _createBundleCheckout(
  Request request,
  AppDependencies dependencies,
  AppConfig config,
  BundleService service,
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

  final String bundleId = body.requireString('bundle_id');
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
          'Le prestataire de paiement ne vend pas de bundle sur ce poste : '
          'la commande est indisponible.',
    );
  }

  final BundleOrder order = await service.order(
    buyerId: auth.userId,
    bundleId: bundleId,
    successUrl: successUrl,
    cancelUrl: cancelUrl,
    gateway: gateway,
    promoCode: promoCode,
    idempotencyKey: idempotencyKey,
  );

  await dependencies.audit.record(
    AuditEntry(
      userId: auth.userId,
      action: bundleCheckoutStartedAction,
      targetType: 'bundle',
      targetId: order.bundleId,
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

/// La représentation JSON d'un bundle, avec le titre de ses livres.
///
/// Les titres viennent de la vente des livres : c'est le titre que le
/// lecteur voit dans la vitrine, pas le titre du manuscrit. L'ordre est
/// celui du bundle : c'est lui qui fait le bundle.
Future<Map<String, Object?>> _bundleJson(
  BundleRecord bundle,
  BookSaleStore sales, {
  required bool isPublic,
  ProjectStore? projects,
}) async {
  final List<Map<String, Object?>> books = <Map<String, Object?>>[];
  for (final String projectId in bundle.projectIds) {
    if (isPublic) {
      // Un livre en vente n'est pas pour autant dans la vitrine : un livre
      // que son auteur n'a pas publie n'a rien a faire dans la vitrine
      // d'un bundle. Son identifiant ne sort pas d'ici.
      final ProjectRecord? project = projects == null
          ? null
          : await projects.findPublic(projectId: projectId);
      if (project == null) continue;
    }
    final BookSaleRecord? sale = await sales.findByProject(projectId);
    books.add(<String, Object?>{
      'project_id': projectId,
      'title': sale?.title ?? '',
    });
  }
  return <String, Object?>{
    ...(isPublic ? bundle.toPublicJson() : bundle.toJson()),
    'books': books,
  };
}

/// La liste des livres du bundle demandée par le client.
///
/// La liste est **ordonnée** : l'ordre fait partie du bundle. Le corps de
/// la requête est la frontière où les données se valident : une liste qui
/// ne porte pas des identifiants de livres est refusée ici, avant le
/// service.
List<String> _readProjectIds(JsonBody body) {
  final List<dynamic> raw = body.requireList('project_ids', minLength: 1);
  final List<String> projectIds = <String>[];
  for (final Object? value in raw) {
    if (value is! String || value.trim().isEmpty) {
      throw ValidationException(
        field: 'project_ids',
        message:
            'Le champ « project_ids » doit porter des identifiants de livres.',
      );
    }
    projectIds.add(value.trim());
  }
  return projectIds;
}
