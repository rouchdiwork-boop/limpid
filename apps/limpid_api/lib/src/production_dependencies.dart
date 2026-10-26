import 'package:postgres/postgres.dart';

import 'auth/jwks.dart';
import 'auth/jwt_verifier.dart';
import 'config/app_config.dart';
import 'db/account_purge_store.dart';
import 'db/admin_database.dart';
import 'db/audit_log.dart';
import 'db/comment_store.dart';
import 'db/database.dart';
import 'db/migration_runner.dart';
import 'db/postgres_admin_database.dart';
import 'db/postgres_audit_log.dart';
import 'db/postgres_project_store.dart';
import 'db/postgres_sync_store.dart';
import 'db/postgres_team_database.dart';
import 'db/postgres_two_factor_database.dart';
import 'db/project_store.dart';
import 'db/quota_database.dart';
import 'db/sql_account_purge_store.dart';
import 'db/sql_quota_database.dart';
import 'db/sqlite_admin_database.dart';
import 'db/sqlite_audit_log.dart';
import 'db/sqlite_database.dart';
import 'db/sqlite_migration_runner.dart';
import 'db/sqlite_project_store.dart';
import 'db/sqlite_sync_store.dart';
import 'db/sqlite_team_database.dart';
import 'db/sqlite_two_factor_database.dart';
import 'db/sync_store.dart';
import 'db/team_database.dart';
import 'db/two_factor_database.dart';
import 'dependencies.dart';
import 'logging/logger.dart';
import 'redis/key_value_store.dart';
import 'redis/redis_client.dart';
import 'services/account_purge.dart';
import 'services/account_purge_scheduler.dart';
import 'services/ai_gateway.dart';
import 'services/limpid_ai_gateway.dart';
import 'services/payment_gateway.dart';
import 'services/sync_hub.dart';
import 'storage/object_storage.dart';

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
    ),
    interval: config.purgeInterval,
    logger: logger,
  );
  purgeScheduler.start();

  return AppDependencies(
    projects: stores.projects,
    sync: stores.sync,
    audit: stores.audit,
    comments: stores.comments,
    purge: stores.purge,
    quotas: stores.quotas,
    twoFactor: stores.twoFactor,
    teams: stores.teams,
    admin: stores.admin,
    ai: _buildAiGateway(config),
    payments: _buildPaymentGateway(config),
    storage: _buildObjectStorage(config),
    keyValue: keyValue,
    jwtVerifier: JwtVerifier(jwks: jwks, expectedIssuer: config.expectedIssuer),
    logger: logger,
    databaseProbe: stores.probe,
    syncHub: SyncHub(),
    shutdown: () async {
      await purgeScheduler.stop();
      await stores.close();
      await resolvedRedis?.close();
    },
  );
}

/// The persistence ports of the API, whatever the engine behind them.
final class _Stores {
  const _Stores({
    required this.projects,
    required this.sync,
    required this.audit,
    required this.comments,
    required this.purge,
    required this.quotas,
    required this.twoFactor,
    required this.teams,
    required this.admin,
    required this.probe,
    required this.close,
  });

  final ProjectStore projects;
  final SyncStore sync;
  final AuditLog audit;
  final CommentStore comments;
  final AccountPurgeStore purge;
  final QuotaDatabase quotas;
  final TwoFactorDatabase twoFactor;
  final TeamDatabase teams;
  final AdminDatabase admin;
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
    quotas: quotas,
    twoFactor: PostgresTwoFactorDatabase(resolvedPool),
    teams: PostgresTeamDatabase(resolvedPool, planLookup: _planLookupOf(quotas)),
    admin: PostgresAdminDatabase(resolvedPool),
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
    quotas: quotas,
    twoFactor: SqliteTwoFactorDatabase(resolved),
    teams: SqliteTeamDatabase(resolved, planLookup: _planLookupOf(quotas)),
    admin: SqliteAdminDatabase(resolved),
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
