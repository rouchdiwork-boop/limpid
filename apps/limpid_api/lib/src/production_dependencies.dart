import 'package:postgres/postgres.dart';

import 'auth/account_auth_deletion.dart';
import 'auth/jwks.dart';
import 'auth/jwt_verifier.dart';
import 'auth/supabase_account_admin.dart';
import 'config/app_config.dart';
import 'db/account_purge_external_store.dart';
import 'db/account_purge_store.dart';
import 'db/admin_database.dart';
import 'db/audit_log.dart';
import 'db/book_sale_store.dart';
import 'db/comment_store.dart';
import 'db/database.dart';
import 'db/entitlement_store.dart';
import 'db/export_job_store.dart';
import 'db/kdp_database.dart';
import 'db/kdp_deposit_store.dart';
import 'db/migration_runner.dart';
import 'db/postgres_admin_database.dart';
import 'db/postgres_audit_log.dart';
import 'db/postgres_book_sale_store.dart';
import 'db/postgres_entitlement_store.dart';
import 'db/postgres_export_job_store.dart';
import 'db/postgres_kdp_database.dart';
import 'db/postgres_kdp_deposit_store.dart';
import 'db/postgres_project_store.dart';
import 'db/postgres_promo_code_store.dart';
import 'db/postgres_share_store.dart';
import 'db/postgres_stripe_event_database.dart';
import 'db/postgres_sync_store.dart';
import 'db/postgres_team_database.dart';
import 'db/postgres_two_factor_database.dart';
import 'db/postgres_webhook_database.dart';
import 'db/project_store.dart';
import 'db/promo_code_store.dart';
import 'db/quota_database.dart';
import 'db/share_store.dart';
import 'db/sql_account_purge_external_store.dart';
import 'db/sql_account_purge_store.dart';
import 'db/sql_quota_database.dart';
import 'db/sqlite_admin_database.dart';
import 'db/sqlite_audit_log.dart';
import 'db/sqlite_book_sale_store.dart';
import 'db/sqlite_database.dart';
import 'db/sqlite_entitlement_store.dart';
import 'db/sqlite_export_job_store.dart';
import 'db/sqlite_kdp_database.dart';
import 'db/sqlite_kdp_deposit_store.dart';
import 'db/sqlite_migration_runner.dart';
import 'db/sqlite_project_store.dart';
import 'db/sqlite_promo_code_store.dart';
import 'db/sqlite_share_store.dart';
import 'db/sqlite_stripe_event_database.dart';
import 'db/sqlite_sync_store.dart';
import 'db/sqlite_team_database.dart';
import 'db/sqlite_two_factor_database.dart';
import 'db/sqlite_webhook_database.dart';
import 'db/stripe_event_database.dart';
import 'db/sync_store.dart';
import 'db/team_database.dart';
import 'db/two_factor_database.dart';
import 'db/webhook_database.dart';
import 'dependencies.dart';
import 'logging/logger.dart';
import 'redis/key_value_store.dart';
import 'redis/redis_client.dart';
import 'services/account_purge.dart';
import 'services/account_purge_scheduler.dart';
import 'services/ai_gateway.dart';
import 'services/amazon_kdp_gateway.dart';
import 'services/api_access_guard.dart';
import 'services/feature_flag_service.dart';
import 'services/kdp_gateway.dart';
import 'services/limpid_ai_gateway.dart';
import 'services/payment_gateway.dart';
import 'services/sync_hub.dart';
import 'services/webhook_dispatcher.dart';
import 'storage/object_storage.dart';
import 'worker/export_worker_loop.dart';

/// The directory holding the SQL migrations of Postgres.
const String defaultMigrationsDirectory = 'db/migrations';

/// The directory holding the SQL migrations of SQLite.
const String defaultSqliteMigrationsDirectory = 'db/migrations/sqlite';

/// Builds the dependencies of the production server.
///
/// The engine is chosen by the configuration: SQLite, the default, opens a
/// local file and applies the migrations of `db/migrations/sqlite`; Postgres
/// opens the pool described by `DATABASE_URL` and applies the migrations of
/// `db/migrations`.
///
/// The services that are not configured are replaced by explicit
/// implementations refusing the call with a clean error, so a development
/// workstation boots without any secret.
Future<AppDependencies> buildProductionDependencies(
  AppConfig config, {
  Pool<Object?>? pool,
  RedisClient? redis,
  SqliteDatabase? sqliteDatabase,
  String migrationsDirectory = defaultMigrationsDirectory,
  String sqliteMigrationsDirectory = defaultSqliteMigrationsDirectory,
}) async {
  final Logger logger = Logger(level: config.logLevel);
  logger.info('server.config', <String, Object?>{
    'profile': config.profile.label,
    'driver': config.databaseDriver.label,
  });

  final _Stores stores = switch (config.databaseDriver) {
    DatabaseDriver.postgres => await _postgresStores(
      config,
      logger: logger,
      pool: pool,
      migrationsDirectory: migrationsDirectory,
    ),
    DatabaseDriver.sqlite => await _sqliteStores(
      config,
      logger: logger,
      database: sqliteDatabase,
      migrationsDirectory: sqliteMigrationsDirectory,
    ),
  };

  final RedisClient? resolvedRedis =
      redis ?? await _connectRedis(config, logger);
  final KeyValueStore keyValue = resolvedRedis == null
      ? const DisabledKeyValueStore()
      : RedisKeyValueStore(resolvedRedis);

  final HttpJwksProvider jwks = HttpJwksProvider(
    url: config.supabaseJwksUrl,
    ttl: config.jwksCacheTtl,
  );

  // Le worker de purge démarre avec le serveur et s'arrête avec lui : les
  // comptes dont le délai de trente jours est passé sont effacés sans que
  // personne ait à demander (D-19).
  final AccountPurgeScheduler purgeScheduler = AccountPurgeScheduler(
    service: AccountPurgeService(
      store: stores.purge,
      audit: stores.audit,
      logger: logger,
      // La purge ne se contente pas de la base de l'API : le compte doit
      // disparaitre du service d'authentification et les artefacts du
      // stockage distant doivent etre effaces. Sans ces deux ports, la
      // promesse faite a l'auteur (« vos donnees seront effacees ») ne
      // serait tenue que pour la base.
      external: stores.purgeExternal,
      auth: _buildAccountAuthDeletion(config),
      storage: _buildObjectStorageDeletion(config),
    ),
    interval: config.purgeInterval,
    logger: logger,
  );
  purgeScheduler.start();

  // Le worker d'export demarre avec le serveur et s'arrete avec lui : un
  // travail demande reste en attente dans la base, et le premier tour de
  // la boucle le trouve apres un redemarrage.
  late final ExportWorkerLoop exportWorker;

  final AppDependencies dependencies = AppDependencies(
    projects: stores.projects,
    sync: stores.sync,
    audit: stores.audit,
    comments: stores.comments,
    purge: stores.purge,
    quotas: stores.quotas,
    twoFactor: stores.twoFactor,
    teams: stores.teams,
    admin: stores.admin,
    webhooks: stores.webhooks,
    shares: stores.shares,
    bookSales: stores.bookSales,
    entitlements: stores.entitlements,
    promoCodes: stores.promoCodes,
    kdp: stores.kdp,
    kdpDeposits: stores.kdpDeposits,
    stripeEvents: stores.stripeEvents,
    kdpGateway: _buildKdpGateway(config),
    // Le dispatcher est garde par le plan : un compte qui a quitte Studio
    // ne recoit plus ses livraisons, meme si ses points de rappel sont
    // toujours enregistres.
    // Les indicateurs du back-office : un indicateur dont la clef est une
    // capacite de formule coupe cette capacite pour tout le monde, sans
    // redéploiement. Le service n'existe que si le back-office est câblé.
    featureFlags: FeatureFlagService(
      source: AdminFeatureFlagSource(stores.admin),
      logger: logger,
    ),
    webhookDispatcher: WebhookDispatcher(
      database: stores.webhooks,
      guard: ApiAccessGuard(planOf: _planLookupOf(stores.quotas)),
      // En developpement, l'auteur teste sa livraison contre un rappel
      // local. En production, un rappel qui se resout vers le reseau du
      // deploiement est refuse.
      allowPrivateHosts: !config.profile.isStrict,
    ),
    ai: _buildAiGateway(config),
    payments: _buildPaymentGateway(config),
    storage: _buildObjectStorage(config),
    keyValue: keyValue,
    jwtVerifier: JwtVerifier(jwks: jwks, expectedIssuer: config.expectedIssuer),
    logger: logger,
    databaseProbe: stores.probe,
    syncHub: SyncHub(),
    shutdown: () async {
      await exportWorker.stop();
      await purgeScheduler.stop();
      await stores.close();
      await resolvedRedis?.close();
    },
  );

  exportWorker = buildExportWorkerLoop(dependencies, jobs: stores.exportJobs);
  await exportWorker.start();

  return dependencies;
}

/// The persistence ports of the API, whatever the engine behind them.
final class _Stores {
  const _Stores({
    required this.projects,
    required this.sync,
    required this.audit,
    required this.comments,
    required this.purge,
    required this.purgeExternal,
    required this.quotas,
    required this.twoFactor,
    required this.teams,
    required this.admin,
    required this.webhooks,
    required this.shares,
    required this.bookSales,
    required this.entitlements,
    required this.promoCodes,
    required this.exportJobs,
    required this.kdp,
    required this.kdpDeposits,
    required this.stripeEvents,
    required this.probe,
    required this.close,
  });

  final ProjectStore projects;
  final SyncStore sync;
  final AuditLog audit;
  final CommentStore comments;
  final AccountPurgeStore purge;

  /// The state of the deletions carried out outside the API.
  final AccountPurgeExternalStore purgeExternal;
  final QuotaDatabase quotas;
  final TwoFactorDatabase twoFactor;
  final TeamDatabase teams;
  final AdminDatabase admin;
  final WebhookDatabase webhooks;
  final ShareStore shares;
  final BookSaleStore bookSales;
  final EntitlementStore entitlements;
  final PromoCodeStore promoCodes;
  final ExportJobStore exportJobs;
  final KdpDatabase kdp;
  final KdpDepositStore kdpDeposits;
  final StripeEventDatabase stripeEvents;
  final HealthProbe probe;
  final Future<void> Function() close;
}

/// La lecture de la formule d'un compte, pour les services qui l'exigent.
///
/// Les équipes et la double authentification ne dépendent pas de la base des
/// formules : la composition leur fournit une fonction de lecture.
PlanLookup _planLookupOf(QuotaDatabase quotas) {
  return (String userId) async {
    final AccountPlan? plan = await quotas.planOf(userId);
    return plan?.plan.name;
  };
}

Future<_Stores> _postgresStores(
  AppConfig config, {
  required Logger logger,
  Pool<Object?>? pool,
  required String migrationsDirectory,
}) async {
  final String? databaseUrl = config.databaseUrl;
  if (databaseUrl == null) {
    throw StateError(
      'The Postgres connection string is missing from the configuration.',
    );
  }

  final Pool<Object?> resolvedPool = pool ?? createPool(databaseUrl);
  if (pool == null) {
    final List<String> applied = await MigrationRunner(
      pool: resolvedPool,
      directory: migrationsDirectory,
    ).run();
    if (applied.isNotEmpty) {
      logger.info('migrations.applied', <String, Object?>{
        'count': applied.length,
      });
    }
  }

  final QuotaDatabase quotas = PostgresQuotaDatabase(resolvedPool);

  return _Stores(
    projects: PostgresProjectStore(resolvedPool),
    sync: PostgresSyncStore(resolvedPool),
    audit: PostgresAuditLog(resolvedPool),
    comments: SqlCommentStore(PostgresCommentDatabase(resolvedPool)),
    purge: SqlAccountPurgeStore(PostgresAccountPurgeDatabase(resolvedPool)),
    purgeExternal: SqlAccountPurgeExternalStore(
      PostgresAccountPurgeDatabase(resolvedPool),
    ),
    quotas: quotas,
    twoFactor: PostgresTwoFactorDatabase(resolvedPool),
    teams: PostgresTeamDatabase(
      resolvedPool,
      planLookup: _planLookupOf(quotas),
    ),
    admin: PostgresAdminDatabase(resolvedPool),
    webhooks: PostgresWebhookDatabase(resolvedPool),
    shares: PostgresShareStore(resolvedPool),
    bookSales: PostgresBookSaleStore(resolvedPool),
    entitlements: PostgresEntitlementStore(resolvedPool),
    promoCodes: PostgresPromoCodeStore(resolvedPool),
    exportJobs: PostgresExportJobStore(resolvedPool),
    kdp: PostgresKdpDatabase(
      resolvedPool,
      planLookup: _planLookupOf(quotas),
      artefacts: _buildObjectStorage(config),
    ),
    kdpDeposits: PostgresKdpDepositStore(resolvedPool),
    stripeEvents: PostgresStripeEventDatabase(resolvedPool),
    probe: _PoolHealthProbe(resolvedPool),
    close: () => resolvedPool.close(),
  );
}

Future<_Stores> _sqliteStores(
  AppConfig config, {
  required Logger logger,
  SqliteDatabase? database,
  required String migrationsDirectory,
}) async {
  final SqliteDatabase resolved =
      database ?? await SqliteDatabase.open(config.sqlitePath);
  if (database == null) {
    final List<String> applied = await SqliteMigrationRunner(
      database: resolved,
      directory: migrationsDirectory,
    ).run();
    if (applied.isNotEmpty) {
      logger.info('migrations.applied', <String, Object?>{
        'count': applied.length,
      });
    }
  }

  final QuotaDatabase quotas = SqliteQuotaDatabase(resolved);

  return _Stores(
    projects: SqliteProjectStore(resolved),
    sync: SqliteSyncStore(resolved),
    audit: SqliteAuditLog(resolved),
    comments: SqlCommentStore(SqliteCommentDatabase(resolved)),
    purge: SqlAccountPurgeStore(SqliteAccountPurgeDatabase(resolved)),
    purgeExternal: SqlAccountPurgeExternalStore(
      SqliteAccountPurgeDatabase(resolved),
    ),
    quotas: quotas,
    twoFactor: SqliteTwoFactorDatabase(resolved),
    teams: SqliteTeamDatabase(resolved, planLookup: _planLookupOf(quotas)),
    admin: SqliteAdminDatabase(resolved),
    webhooks: SqliteWebhookDatabase(resolved),
    shares: SqliteShareStore(resolved),
    bookSales: SqliteBookSaleStore(resolved),
    entitlements: SqliteEntitlementStore(resolved),
    promoCodes: SqlitePromoCodeStore(resolved),
    exportJobs: SqliteExportJobStore(resolved),
    kdp: SqliteKdpDatabase(
      resolved,
      planLookup: _planLookupOf(quotas),
      artefacts: _buildObjectStorage(config),
    ),
    kdpDeposits: SqliteKdpDepositStore(resolved),
    stripeEvents: SqliteStripeEventDatabase(resolved),
    probe: _SqliteHealthProbe(resolved),
    close: resolved.close,
  );
}

/// Opens the connection to Redis, when it is configured.
///
/// A Redis that is configured but unreachable does not stop a development
/// server: the cache degrades to a disabled store and the reason is logged.
Future<RedisClient?> _connectRedis(AppConfig config, Logger logger) async {
  final String? url = config.redisUrl;
  if (url == null) return null;
  try {
    return await RedisClient.connect(url);
  } on Object catch (error) {
    if (config.profile.isStrict) rethrow;
    logger.warning('redis.unavailable', <String, Object?>{
      'error': error.toString(),
    });
    return null;
  }
}

AiGateway _buildAiGateway(AppConfig config) {
  if (!config.hasAiProvider) return const UnavailableAiGateway();
  return LimpidAiGateway.anthropic(apiKey: config.anthropicApiKey);
}

PaymentGateway _buildPaymentGateway(AppConfig config) {
  if (!config.hasPayments) return const UnavailablePaymentGateway();
  return StripePaymentGateway(secretKey: config.stripeSecretKey);
}

/// Le canal de distribution chez Amazon KDP.
///
/// Sans identifiants Amazon, le dépôt est **impossible** : le port le dit
/// (`UnavailableKdpGateway`) et la route répond 503 en nommant la raison.
/// Le serveur ne pretended pas que le livre a atteint Amazon.
///
/// Le budget de la chaîne d'appels vient de la requête : la passerelle ne
/// peut pas la dépasser.
KdpGateway _buildKdpGateway(AppConfig config) {
  if (!config.hasKdpDistribution) return const UnavailableKdpGateway();
  return AmazonKdpGateway(
    clientId: config.amazonClientId!,
    clientSecret: config.amazonClientSecret!,
    refreshToken: config.amazonRefreshToken!,
    budget: _kdpBudget(config),
  );
}

/// La réserve laissée à la passerelle pour écrire la trace du dépôt.
///
/// Le middleware du temps de traitement ne coupe pas le gestionnaire : au
/// pire, il répond à l'auteur pendant que le dépôt continue. La réserve
/// laisse à la passerelle le temps de consigner l'issue — une issue
/// inconnue ou un échec — avant que le middleware ne réponde.
const Duration _kdpBudgetReserve = Duration(seconds: 2);

/// Le temps que la chaîne d'appels auprès d'Amazon peut prendre.
///
/// Le budget vient de la requête HTTP : la chaîne entière doit rester dans
/// le temps de la requête, sinon le dépôt continue en arrière-plan pendant
/// que l'auteur reçoit un « temps de traitement dépassé » — et qu'il
/// relance un dossier qu'Amazon a peut-être déjà reçu.
Duration _kdpBudget(AppConfig config) {
  final Duration request = config.requestTimeout;
  if (request <= _kdpBudgetReserve) {
    // Une requête plus courte que la réserve : la passerelle prend les
    // deux tiers du temps disponible.
    return Duration(microseconds: request.inMicroseconds * 2 ~/ 3);
  }
  return request - _kdpBudgetReserve;
}

/// L'effacement du compte dans le service d'authentification.
///
/// Le port est absent quand le poste n'a pas de clé de rôle de service :
/// il n'y a alors aucun compte à effacer de là-bas.
AccountAuthDeletion? _buildAccountAuthDeletion(AppConfig config) {
  if (!config.hasAuthAdmin) return null;
  return SupabaseAccountAdmin(
    baseUrl: config.supabaseUrl,
    serviceRoleKey: config.supabaseServiceRoleKey,
  );
}

/// L'effacement des artefacts dans le stockage distant.
///
/// Seul un stockage qui sait effacer est retenu : sans stockage configuré,
/// il n'y a rien à effacer, et le port absent le dit.
ObjectStorageDeletion? _buildObjectStorageDeletion(AppConfig config) {
  final ObjectStorage storage = _buildObjectStorage(config);
  if (storage is ObjectStorageDeletion) return storage as ObjectStorageDeletion;
  return null;
}

ObjectStorage _buildObjectStorage(AppConfig config) {
  if (!config.hasObjectStorage) return const UnavailableObjectStorage();
  return R2ObjectStorage(
    endpoint: config.r2Endpoint,
    bucket: config.r2Bucket,
    accessKeyId: config.r2AccessKeyId,
    secretAccessKey: config.r2SecretAccessKey,
  );
}

/// A probe running a trivial query on Postgres.
final class _PoolHealthProbe implements HealthProbe {
  const _PoolHealthProbe(this._pool);

  final Pool<Object?> _pool;

  @override
  Future<bool> ping() async {
    try {
      await _pool.execute('SELECT 1');
      return true;
    } on Object {
      return false;
    }
  }
}

/// A probe running a trivial query on SQLite.
final class _SqliteHealthProbe implements HealthProbe {
  const _SqliteHealthProbe(this._database);

  final SqliteDatabase _database;

  @override
  Future<bool> ping() async {
    try {
      await _database.run(() {
        _database.connection.select('SELECT 1');
      });
      return true;
    } on Object {
      return false;
    }
  }
}
