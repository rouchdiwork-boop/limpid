import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/admin_database.dart';
import '../db/book_sale_store.dart';
import '../db/entitlement_store.dart';
import '../db/kdp_database.dart';
import '../db/kdp_deposit_store.dart';
import '../db/promo_code_store.dart';
import '../db/quota_database.dart';
import '../db/share_store.dart';
import '../db/stripe_event_database.dart';
import '../db/team_database.dart';
import '../db/two_factor_database.dart';
import '../db/webhook_database.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../services/book_sale_service.dart';
import '../services/kdp_gateway.dart';
import '../services/kdp_publishing_service.dart';
import '../services/quota_gauges.dart';
import '../services/quota_service.dart';
import '../services/stripe_webhook_service.dart';
import 'account_routes.dart';
import 'admin_routes.dart';
import 'ai_routes.dart';
import 'book_sale_routes.dart';
import 'checkout_routes.dart';
import 'comment_routes.dart';
import 'export_routes.dart';
import 'health_routes.dart';
import 'import_routes.dart';
import 'kdp_publishing_routes.dart';
import 'kdp_routes.dart';
import 'project_routes.dart';
import 'public_api_routes.dart';
import 'publication_routes.dart';
import 'quota_routes.dart';
import 'share_routes.dart';
import 'stripe_webhook_routes.dart';
import 'sync_routes.dart';
import 'sync_socket_routes.dart';
import 'team_routes.dart';
import 'two_factor_routes.dart';
import 'webhook_routes.dart';

/// Builds the router of the API.
///
/// Every route of the contract is registered here; the authentication, the
/// CORS, the timeout and the rate limit are applied by the server, around
/// this router.
Router buildRouter(AppDependencies dependencies, AppConfig config) {
  final Router router = Router(notFoundHandler: _notFound);

  // Le service de quota porte le garde-fou des exports et des appels au
  // modèle. Il n'existe que si la base des formules est câblée.
  final QuotaDatabase? quotaDatabase = dependencies.quotas;
  // Le service de quota est aussi l'emetteur de deux evenements du compte
  // (`plan.changed` et `quota.reached`) : il porte le dispatcher.
  final QuotaService? quota = quotaDatabase == null
      ? null
      : QuotaService(
          database: quotaDatabase,
          dispatcher: dependencies.webhookDispatcher,
        );

  registerHealthRoutes(router, dependencies);
  registerProjectRoutes(router, dependencies, config, quota: quota);
  registerSyncRoutes(router, dependencies, config, quota: quota);
  registerAiRoutes(router, dependencies, config, quota: quota);
  registerExportRoutes(
    router,
    dependencies,
    config,
    quota: quota,
    jobs: dependencies.exportJobs,
  );
  registerCheckoutRoutes(
    router,
    dependencies,
    config,
    sales: dependencies.bookSales,
    entitlements: dependencies.entitlements,
    promoCodes: dependencies.promoCodes,
  );
  registerAccountRoutes(router, dependencies, config);
  registerCommentRoutes(
    router,
    dependencies,
    config,
    comments: dependencies.comments,
  );
  registerPublicationRoutes(router, dependencies, config);
  registerSyncSocketRoute(router, dependencies, config);

  // Les quatre services du lot 7 sont optionnels : un serveur qui ne les
  // câble pas ne sert pas leurs routes, plutôt que de les servir en
  // erreur.
  if (quotaDatabase != null) {
    registerQuotaRoutes(
      router,
      quotaDatabase,
      config,
      audit: dependencies.audit,
      dispatcher: dependencies.webhookDispatcher,
      // Les jauges sont mesurees a l'instant : le nombre de livres, le
      // nombre de mots et le stockage occupe du compte.
      gauges: AccountQuotaGauges(
        projects: dependencies.projects,
        sync: dependencies.sync,
        storage: dependencies.storage,
        pageLimit: config.maxPageLimit,
      ),
      // Les indicateurs du back-office : un indicateur dont la clef est
      // une capacite la coupe pour tout le monde.
      flags: dependencies.featureFlags,
    );
  }
  final TwoFactorDatabase? twoFactor = dependencies.twoFactor;
  if (twoFactor != null) {
    registerTwoFactorRoutes(
      router,
      twoFactor,
      config,
      planOf: dependencies.planOf,
    );
  }
  // La vente d'un livre est facultative : un serveur qui ne vend pas ne
  // sert pas ses routes.
  final BookSaleStore? bookSales = dependencies.bookSales;
  final EntitlementStore? entitlements = dependencies.entitlements;
  final PromoCodeStore? promoCodes = dependencies.promoCodes;
  if (bookSales != null && entitlements != null && promoCodes != null) {
    registerBookSaleRoutes(
      router,
      dependencies,
      config,
      sales: bookSales,
      entitlements: entitlements,
      promoCodes: promoCodes,
    );
  }

  // L'import d'un manuscrit ecrit dans le journal de synchronisation : il
  // ne demande aucun port de plus.
  registerImportRoutes(router, dependencies, config, quota: quota);

  // Le partage en lecture est facultatif : un serveur qui ne le cable pas
  // ne sert pas ses routes.
  final ShareStore? shares = dependencies.shares;
  if (shares != null) {
    registerShareRoutes(router, dependencies, config, shares: shares);
  }
  final TeamDatabase? teams = dependencies.teams;
  if (teams != null) {
    registerTeamRoutes(
      router,
      teams,
      config,
      audit: dependencies.audit,
      dispatcher: dependencies.webhookDispatcher,
    );
  }
  final AdminDatabase? admin = dependencies.admin;
  if (admin != null) {
    registerAdminRoutes(router, admin, config, quota: quota);
  }
  final WebhookDatabase? webhooks = dependencies.webhooks;
  if (webhooks != null) {
    registerWebhookRoutes(
      router,
      webhooks,
      config,
      planOf: dependencies.planOf,
      audit: dependencies.audit,
      dispatcher: dependencies.webhookDispatcher,
    );
    // L'API publique est sur le meme port que le reste, mais elle
    // s'authentifie par sa cle d'API et non par le jeton de session : le
    // serveur l'exempte deja du jeton. Elle n'est servie que si le port
    // des cles est cable.
    registerPublicApiRoutes(
      router,
      config,
      projects: dependencies.projects,
      sync: dependencies.sync,
      webhooks: webhooks,
      planOf: dependencies.planOf,
    );
  }
  final KdpDatabase? kdp = dependencies.kdp;

  // Le dépôt chez Amazon est une seconde étape : elle n'existe que si la
  // préparation, la trace des dépôts et le canal Amazon sont câblés. Un
  // serveur qui ne distribue pas sur Amazon prépare donc une publication
  // et refuse le dépôt — il ne sert pas une route qui échouerait.
  final KdpDepositStore? kdpDeposits = dependencies.kdpDeposits;
  final KdpGateway? kdpGateway = dependencies.kdpGateway;
  if (kdp != null && kdpDeposits != null && kdpGateway != null) {
    // Les depots sont enregistres **avant** les publications : le chemin
    // `/v1/publishing/kdp/deposits` serait sinon avale par la route de
    // lecture d'une publication, qui prend un identifiant a la place.
    registerKdpPublishingRoutes(
      router,
      KdpPublishingService(
        publications: kdp,
        deposits: kdpDeposits,
        gateway: kdpGateway,
      ),
      config,
    );
  }
  if (kdp != null) {
    registerKdpRoutes(router, kdp, config);
  }

  // Le rappel de paiement est ce qui attribue une formule payée : sans
  // lui, aucune formule payée n'existe. Il a besoin de la base des
  // formules et de la table des événements déjà traités.
  final StripeEventDatabase? stripeEvents = dependencies.stripeEvents;
  if (stripeEvents != null && quota != null) {
    // Le rappel traite aussi le paiement d'un livre : le service de la
    // vente accorde le droit de lecture et ecrit la ventilation.
    BookSaleService? bookSalesService;
    final BookSaleStore? sales = dependencies.bookSales;
    final EntitlementStore? entitlements = dependencies.entitlements;
    final PromoCodeStore? promoCodes = dependencies.promoCodes;
    if (sales != null && entitlements != null && promoCodes != null) {
      bookSalesService = BookSaleService(
        sales: sales,
        entitlements: entitlements,
        promoCodes: promoCodes,
        projects: dependencies.projects,
        storage: dependencies.storage,
        audit: dependencies.audit,
      );
    }
    registerStripeWebhookRoutes(
      router,
      StripeWebhookService(
        database: stripeEvents,
        quota: quota,
        audit: dependencies.audit,
        secret: config.stripeWebhookSecret,
        logger: dependencies.logger,
        handledEvents: config.stripeWebhookEvents,
        bookSales: bookSalesService,
      ),
      config,
    );
  }

  return router;
}

Response _notFound(Request request) {
  return ApiResponse.error(
    const NotFoundException(
      message: "Cette route n'existe pas.",
      details: <String, Object?>{'path': 'unknown'},
    ),
  );
}
