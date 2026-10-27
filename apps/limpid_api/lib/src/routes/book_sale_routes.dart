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
import '../db/promo_code_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/admin_service.dart';
import '../services/book_sale_service.dart';
import '../services/promo_code_service.dart';
import '../services/revenue_share_service.dart';

/// L'action journalée quand un auteur met son livre en vente.
const String bookSalePublishedAction = 'book.sale_published';

/// Le nombre de prix publics qu'une adresse IP peut demander d'un coup.
const int publicBookSaleRateLimitCapacity = 60;

/// Le nombre de prix publics qu'une adresse IP regagne par seconde.
const double publicBookSaleRateLimitRefillPerSecond = 2;

/// L'action journalée quand l'administration crée un code promo.
const String promoCodeCreatedAction = 'book.promo_code_created';

/// Enregistre les routes de la vente des livres.
///
/// Les routes décrivent le cycle de vente : l'auteur met son livre en
/// vente, l'acheteur le commande, et l'acheteur télécharge ce qu'il a
/// acheté. Elles s'adressent au compte authentifié, et lisent le compte
/// dans le contexte authentifié — jamais dans le corps de la requête.
///
/// Les magasins sont exigés : un serveur qui ne vend pas de livre ne sert
/// pas ces routes, plutôt que de les servir en erreur.
void registerBookSaleRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  required BookSaleStore sales,
  required EntitlementStore entitlements,
  required PromoCodeStore promoCodes,
  BundleStore? bundles,
}) {
  final BookSaleService service = BookSaleService(
    sales: sales,
    entitlements: entitlements,
    promoCodes: promoCodes,
    projects: dependencies.projects,
    storage: dependencies.storage,
    audit: dependencies.audit,
  );
  final PromoCodeService promos = PromoCodeService(store: promoCodes);

  // -------------------------------------------------------------------
  // La mise en vente, par le propriétaire du livre.
  // -------------------------------------------------------------------

  router.put('/v1/books/<projectId>/sale', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final int priceCents = body.requireInt('price_cents', min: 0);
    final String currency = body.requireString('currency');
    final BookSaleStatus status = _readStatus(body);
    final int? authorShare = body.optionalInt(
      'author_share',
      min: 0,
      max: revenueShareTotal,
    );
    final String? artifactKey = body.optionalString('artifact_key');

    final BookSaleRecord sale = await service.publish(
      ownerId: auth.userId,
      projectId: projectId,
      priceInCents: priceCents,
      currency: currency,
      status: status,
      authorShare: authorShare,
      artifactKey: artifactKey,
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: bookSalePublishedAction,
        targetType: 'book_sale',
        targetId: projectId,
        metadata: <String, Object?>{
          'price_cents': sale.priceInCents,
          'currency': sale.currency,
          'status': sale.status.key,
          'author_share': sale.authorShare,
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(sale.toJson());
  });

  // -------------------------------------------------------------------
  // Le prix du livre, pour la page de vente.
  // -------------------------------------------------------------------

  router.get('/v1/books/<projectId>/sale', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final BookSaleRecord? sale = await service.saleOf(projectId);
    if (sale == null) {
      throw const NotFoundException(message: "Ce livre n'est pas en vente.");
    }
    if (!sale.isPublished && sale.ownerId != auth.userId) {
      // Un livre en préparation n'existe que pour son auteur : la réponse
      // ne dit pas à un tiers que le livre existe.
      throw const NotFoundException(message: "Ce livre n'est pas en vente.");
    }
    return ApiResponse.ok(sale.toJson());
  });

  // Le prix est public : la page de vente se regarde sans compte, et le
  // lecteur n'en fait un que pour acheter. La route répond sous le
  // préfixe public de la vitrine — elle est donc exemptée du jeton — et
  // elle est limitée comme elle, puisque c'est la seule qu'un inconnu
  // peut appeler en boucle.
  final TokenBucketRateLimiter publicPriceLimiter = TokenBucketRateLimiter(
    capacity: publicBookSaleRateLimitCapacity,
    refillPerSecond: publicBookSaleRateLimitRefillPerSecond,
  );

  router.get('/v1/public/books/<projectId>/sale', (
    Request request,
    String projectId,
  ) {
    return rateLimitMiddleware(
      limiter: publicPriceLimiter,
      scope: 'public_book_sale',
      applies: (Request request) => true,
    )((Request request) async {
      final BookSaleRecord? sale = await service.saleOf(projectId);
      if (sale == null || !sale.isPublished) {
        // Un livre inconnu, un livre qui n'est pas en vente et un livre en
        // préparation répondent la même chose : le visiteur ne doit pas
        // apprendre qu'un livre existe.
        throw const NotFoundException(message: "Ce livre n'est pas en vente.");
      }
      // Un livre en vente n'est pas pour autant dans la vitrine : son
      // auteur peut le vendre sans l'avoir publié. La vitrine ne montre
      // que les livres publiés.
      final ProjectRecord? project = await service.projects.findPublic(
        projectId: projectId,
      );
      if (project == null) {
        throw const NotFoundException(message: "Ce livre n'est pas en vente.");
      }
      // La réponse ne porte que ce qu'un lecteur a le droit de voir : le
      // prix, le titre et la devise. La part de l'auteur et l'identité du
      // propriétaire restent sur le serveur.
      return ApiResponse.ok(<String, Object?>{
        'project_id': sale.projectId,
        'title': sale.title,
        'price_cents': sale.priceInCents,
        'currency': sale.currency,
        'status': sale.status.key,
        'is_free': sale.isFree,
      });
    })(request);
  });

  // -------------------------------------------------------------------
  // Les livres achetés par le compte.
  // -------------------------------------------------------------------

  router.get('/v1/purchases', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final List<BookPurchase> purchases = await service.purchases(auth.userId);
    // Un livre achete par un bundle montre le bundle qui l'a porte : c'est
    // la provenance de l'achat, et l'acheteur la cherche.
    final Map<String, String> bundleTitles = await _bundleTitlesOf(
      bundles,
      purchases,
    );
    return ApiResponse.ok(
      purchases
          .map(
            (BookPurchase purchase) => <String, Object?>{
              ...purchase.toJson(),
              if (bundleTitles[purchase.bundleId] != null)
                'bundle_title': bundleTitles[purchase.bundleId],
            },
          )
          .toList(growable: false),
    );
  });

  // -------------------------------------------------------------------
  // Le téléchargement d'un livre acheté.
  // -------------------------------------------------------------------

  router.get('/v1/purchases/<projectId>/download', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final BookDownload download = await service.download(
      userId: auth.userId,
      projectId: projectId,
    );
    return ApiResponse.ok(download.toJson());
  });

  // -------------------------------------------------------------------
  // La création d'un code promo, par l'administration.
  // -------------------------------------------------------------------

  router.post('/v1/admin/promo-codes', (Request request) async {
    final AuthContext admin = AdminService.requireAdmin(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String code = body.requireString('code');
    final PromoDiscountType discountType = _readDiscountType(body);
    final int value = body.requireInt('value', min: 0);
    final int maxUses = body.requireInt('max_uses', min: 1);
    final int maxUsesPerAccount =
        body.optionalInt('max_uses_per_account', min: 1) ?? 1;
    final DateTime expiresAt = _readDate(body, 'expires_at');
    final String currency = (body.optionalString('currency') ?? 'eur')
        .trim()
        .toLowerCase();

    final PromoCodeRecord record = await promos.create(
      code: code,
      discountType: discountType,
      value: value,
      maxUses: maxUses,
      maxUsesPerAccount: maxUsesPerAccount,
      expiresAt: expiresAt,
      currency: currency,
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: admin.userId,
        action: promoCodeCreatedAction,
        targetType: 'promo_code',
        targetId: record.code,
        metadata: <String, Object?>{
          'discount_type': record.discountType.key,
          'value': record.value,
          'max_uses': record.maxUses,
          'max_uses_per_account': record.maxUsesPerAccount,
          'expires_at': record.expiresAt.toUtc().toIso8601String(),
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(record.toJson(), status: HttpStatus.created);
  });
}

/// Les titres des bundles qui ont porté les achats [purchases].
///
/// Un bundle est relu une seule fois, même quand il a porté plusieurs
/// livres : la liste des achats d'un compte est courte, et le serveur ne
/// relit pas le même bundle pour chaque livre.
Future<Map<String, String>> _bundleTitlesOf(
  BundleStore? bundles,
  List<BookPurchase> purchases,
) async {
  if (bundles == null) return const <String, String>{};
  final Map<String, String> titles = <String, String>{};
  for (final BookPurchase purchase in purchases) {
    final String? bundleId = purchase.bundleId;
    if (bundleId == null || titles.containsKey(bundleId)) continue;
    final BundleRecord? bundle = await bundles.findById(bundleId);
    if (bundle != null) titles[bundleId] = bundle.title;
  }
  return titles;
}

/// L'état de la vente demandé par le client.
BookSaleStatus _readStatus(JsonBody body) {
  final String raw = (body.optionalString('status') ?? 'published').trim();
  final BookSaleStatus? status = BookSaleStatus.parse(raw);
  if (status == null) {
    throw ValidationException(
      field: 'status',
      message:
          'Le champ « status » doit valoir '
          '${BookSaleStatus.values.map((BookSaleStatus value) => value.key).join(', ')}.',
    );
  }
  return status;
}

/// Le type de remise demandé par le client.
PromoDiscountType _readDiscountType(JsonBody body) {
  final String raw = body.requireString('discount_type');
  final PromoDiscountType? type = PromoDiscountType.parse(raw);
  if (type == null) {
    throw ValidationException(
      field: 'discount_type',
      message:
          'Le champ « discount_type » doit valoir '
          '${PromoDiscountType.values.map((PromoDiscountType value) => value.key).join(', ')}.',
    );
  }
  return type;
}

/// La date d'expiration demandée par le client.
DateTime _readDate(JsonBody body, String field) {
  final String raw = body.requireString(field);
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ValidationException(
      field: field,
      message:
          'Le champ « $field » doit porter une date au format '
          'AAAA-MM-JJTHH:MM:SSZ.',
    );
  }
  return parsed.toUtc();
}
