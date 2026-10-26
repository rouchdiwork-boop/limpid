import '../errors/app_exception.dart';

/// Log levels emitted by the structured logger.
enum LogLevel {
  /// Verbose diagnostics.
  debug,

  /// Routine operational events.
  info,

  /// Recoverable anomalies.
  warning,

  /// Failures that stop the request.
  error;

  /// The textual level used in the JSON logs.
  String get label => name;

  /// Parses a level, defaulting to [LogLevel.info].
  static LogLevel parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return LogLevel.info;
    for (final LogLevel level in LogLevel.values) {
      if (level.label == raw.trim().toLowerCase()) return level;
    }
    return LogLevel.info;
  }
}

/// The profile the API runs under.
///
/// The profile decides how strict the configuration is: the development
/// profile accepts a workstation without any secret, the production profile
/// refuses to start when a variable is missing.
enum LimpidProfile {
  /// The development profile.
  ///
  /// The remote services are optional: a missing service is replaced by an
  /// explicit placeholder, and the routes needing it answer a clean error
  /// instead of crashing the server.
  dev('dev'),

  /// The production profile.
  ///
  /// Every variable is mandatory: the server refuses to start when one is
  /// missing, so a production deployment never runs on a placeholder.
  prod('prod');

  const LimpidProfile(this.label);

  /// The textual name of the profile, as read from `LIMPID_PROFILE`.
  final String label;

  /// Whether the profile demands every variable.
  bool get isStrict => this == LimpidProfile.prod;

  /// Parses a profile, defaulting to [dev].
  ///
  /// Throws a [ConfigException] naming `LIMPID_PROFILE` when the value is
  /// unknown.
  static LimpidProfile parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return LimpidProfile.dev;
    final String candidate = raw.trim().toLowerCase();
    for (final LimpidProfile profile in LimpidProfile.values) {
      if (profile.label == candidate) return profile;
    }
    if (candidate == 'production') return LimpidProfile.prod;
    throw ConfigException(
      variable: 'LIMPID_PROFILE',
      message:
          'La variable d\'environnement LIMPID_PROFILE doit valoir '
          '« dev » ou « prod ».',
    );
  }
}

/// The engine backing the persistence ports.
///
/// SQLite is the default: a fresh workstation boots the API without
/// installing Postgres. Postgres stays the target of the production
/// deployments.
enum DatabaseDriver {
  /// The local SQLite file.
  sqlite('sqlite'),

  /// The Postgres server.
  postgres('postgres');

  const DatabaseDriver(this.label);

  /// The textual name of the driver, as read from `LIMPID_DB_DRIVER`.
  final String label;

  /// Parses a driver, defaulting to [sqlite].
  ///
  /// Throws a [ConfigException] naming `LIMPID_DB_DRIVER` when the value is
  /// unknown.
  static DatabaseDriver parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return DatabaseDriver.sqlite;
    final String candidate = raw.trim().toLowerCase();
    for (final DatabaseDriver driver in DatabaseDriver.values) {
      if (driver.label == candidate) return driver;
    }
    throw ConfigException(
      variable: 'LIMPID_DB_DRIVER',
      message:
          'La variable d\'environnement LIMPID_DB_DRIVER doit valoir '
          '« sqlite » ou « postgres ».',
    );
  }
}

/// The URL used in place of a remote service in the development profile.
///
/// The `.invalid` domain is reserved by the RFC 2606 and never resolves: a
/// request reaching such a service fails fast instead of reaching the
/// network.
const String devPlaceholderUrl = 'https://localhost.invalid';

/// The credential used in place of a real secret in the development profile.
const String devPlaceholderSecret = 'dev-placeholder';

/// The default path of the SQLite file, relative to the working directory.
const String defaultSqlitePath = '.limpid/limpid.db';

/// The default delay between two passes of the purge worker.
///
/// The worker erases the accounts whose deletion request has reached its
/// deadline (D-19). The delay is the time the server waits before looking
/// for them again.
const Duration defaultAccountPurgeInterval = Duration(hours: 1);

/// The delay between two beats of a connection of the real-time relay.
///
/// The relay sends a `ping` to the clients that stayed silent, and the
/// clients answer. The beat keeps the presence of the peers alive
/// (ARCHITECTURE.md §6.6).
const Duration defaultRelayHeartbeatInterval = Duration(seconds: 25);

/// The delay after which a silent connection of the relay is purged.
///
/// The peer that stopped beating is removed from the room, and the other
/// peers are told that it is gone.
const Duration defaultRelayPresenceTimeout = Duration(seconds: 30);

/// Immutable configuration of the API, built from environment variables.
///
/// Every mandatory variable is validated when the configuration is built: a
/// missing or malformed value raises a [ConfigException] naming the variable,
/// so a misconfigured deployment fails at boot instead of at the first
/// request.
///
/// The [profile] decides how strict the validation is. In the development
/// profile the remote services are optional and replaced by explicit
/// placeholders; in the production profile every variable is mandatory.
final class AppConfig {
  /// Creates a configuration.
  const AppConfig({
    required this.profile,
    required this.databaseDriver,
    required this.sqlitePath,
    required this.databaseUrl,
    required this.port,
    required this.supabaseUrl,
    required this.supabaseJwksUrl,
    required this.supabaseAnonKey,
    this.supabaseServiceRoleKey = devPlaceholderSecret,
    this.hasAuthAdmin = false,
    required this.redisUrl,
    required this.r2AccountId,
    required this.r2AccessKeyId,
    required this.r2SecretAccessKey,
    required this.r2Bucket,
    required this.r2Endpoint,
    required this.anthropicApiKey,
    required this.stripeSecretKey,
    this.amazonClientId,
    this.amazonClientSecret,
    this.amazonRefreshToken,
    this.stripeWebhookSecret,
    this.stripeWebhookEvents = const <String>[],
    required this.hasRedis,
    required this.hasObjectStorage,
    required this.hasAiProvider,
    required this.hasPayments,
    required this.logLevel,
    required this.allowedOrigins,
    required this.requestTimeout,
    required this.maxBodyBytes,
    required this.aiRateLimitCapacity,
    required this.aiRateLimitRefillPerSecond,
    required this.apiRateLimitCapacity,
    required this.apiRateLimitRefillPerSecond,
    required this.maxOperationsPerBatch,
    required this.defaultPageLimit,
    required this.maxPageLimit,
    required this.jwksCacheTtl,
    required this.purgeInterval,
    this.relayHeartbeatInterval = defaultRelayHeartbeatInterval,
    this.relayPresenceTimeout = defaultRelayPresenceTimeout,
  });

  /// Builds the configuration from an environment map.
  ///
  /// Throws a [ConfigException] when a mandatory variable is missing or when a
  /// value cannot be parsed. The strictness depends on the profile: the
  /// development profile accepts a workstation without any secret, the
  /// production profile demands every variable.
  factory AppConfig.fromEnvironment(Map<String, String> environment) {
    final LimpidProfile profile = LimpidProfile.parse(
      environment['LIMPID_PROFILE'],
    );
    final DatabaseDriver databaseDriver = DatabaseDriver.parse(
      environment['LIMPID_DB_DRIVER'],
    );
    final bool strict = profile.isStrict;

    final String port = _required(environment, 'PORT', fallback: '8080');
    final int? parsedPort = int.tryParse(port);
    if (parsedPort == null || parsedPort < 0 || parsedPort > 65535) {
      throw ConfigException(
        variable: 'PORT',
        message: 'La variable PORT doit être un entier entre 0 et 65535.',
      );
    }

    final String supabaseUrl = _serviceUrl(
      environment,
      'SUPABASE_URL',
      strict: strict,
    );
    final String jwksUrl =
        _optional(environment, 'SUPABASE_JWKS_URL') ??
        '$supabaseUrl/auth/v1/.well-known/jwks.json';
    _requireAbsoluteUrl(jwksUrl, 'SUPABASE_JWKS_URL');

    final String? redisUrl = strict
        ? _required(environment, 'REDIS_URL')
        : _optional(environment, 'REDIS_URL');
    if (redisUrl != null) {
      _requireAbsoluteUrl(redisUrl, 'REDIS_URL');
    }

    final String r2AccountId = _serviceSecret(
      environment,
      'R2_ACCOUNT_ID',
      strict: strict,
    );
    final String r2Endpoint =
        _optional(environment, 'R2_ENDPOINT') ??
        'https://$r2AccountId.r2.cloudflarestorage.com';
    _requireAbsoluteUrl(r2Endpoint, 'R2_ENDPOINT');

    final String? databaseUrl = databaseDriver == DatabaseDriver.postgres
        ? _required(environment, 'DATABASE_URL')
        : _optional(environment, 'DATABASE_URL');

    final String? anthropicApiKey = strict
        ? _required(environment, 'ANTHROPIC_API_KEY')
        : _optional(environment, 'ANTHROPIC_API_KEY');
    final String? stripeSecretKey = strict
        ? _required(environment, 'STRIPE_SECRET_KEY')
        : _optional(environment, 'STRIPE_SECRET_KEY');
    final String? r2AccessKeyId = strict
        ? _required(environment, 'R2_ACCESS_KEY_ID')
        : _optional(environment, 'R2_ACCESS_KEY_ID');
    final String? r2SecretAccessKey = strict
        ? _required(environment, 'R2_SECRET_ACCESS_KEY')
        : _optional(environment, 'R2_SECRET_ACCESS_KEY');
    final String? r2Bucket = strict
        ? _required(environment, 'R2_BUCKET')
        : _optional(environment, 'R2_BUCKET');
    final String? supabaseServiceRoleKey = strict
        ? _required(environment, 'SUPABASE_SERVICE_ROLE_KEY')
        : _optional(environment, 'SUPABASE_SERVICE_ROLE_KEY');
    // Les identifiants de l'intégration Amazon sont facultatifs dans les
    // deux profils : un serveur qui n'en a pas refuse proprement les
    // dépôts, il ne refuse pas de démarrer.
    final String? amazonClientId = _optional(
      environment,
      'AMAZON_KDP_CLIENT_ID',
    );
    final String? amazonClientSecret = _optional(
      environment,
      'AMAZON_KDP_CLIENT_SECRET',
    );
    final String? amazonRefreshToken = _optional(
      environment,
      'AMAZON_KDP_REFRESH_TOKEN',
    );
    // Le secret du webhook Stripe est facultatif dans les deux profils :
    // un serveur qui ne l'a pas refuse proprement les livraisons, il ne
    // refuse pas de démarrer.
    final String? stripeWebhookSecret = _optional(
      environment,
      'STRIPE_WEBHOOK_SECRET',
    );
    // Les identifiants des événements traités par le webhook. La liste est
    // vide quand la variable est absente : le webhook traite alors tous
    // les événements de l'abonnement.
    final List<String> stripeWebhookEvents = _parseList(
      environment['STRIPE_WEBHOOK_EVENTS'],
    );

    return AppConfig(
      profile: profile,
      databaseDriver: databaseDriver,
      sqlitePath: _optional(environment, 'LIMPID_DB_PATH') ?? defaultSqlitePath,
      databaseUrl: databaseUrl,
      port: parsedPort,
      supabaseUrl: supabaseUrl,
      supabaseJwksUrl: jwksUrl,
      supabaseAnonKey: _serviceSecret(
        environment,
        'SUPABASE_ANON_KEY',
        strict: strict,
      ),
      supabaseServiceRoleKey: supabaseServiceRoleKey ?? devPlaceholderSecret,
      hasAuthAdmin: supabaseServiceRoleKey != null,
      redisUrl: redisUrl,
      r2AccountId: r2AccountId,
      r2AccessKeyId: r2AccessKeyId ?? devPlaceholderSecret,
      r2SecretAccessKey: r2SecretAccessKey ?? devPlaceholderSecret,
      r2Bucket: r2Bucket ?? devPlaceholderSecret,
      r2Endpoint: r2Endpoint,
      anthropicApiKey: anthropicApiKey ?? devPlaceholderSecret,
      stripeSecretKey: stripeSecretKey ?? devPlaceholderSecret,
      stripeWebhookSecret: stripeWebhookSecret,
      stripeWebhookEvents: stripeWebhookEvents,
      amazonClientId: amazonClientId,
      amazonClientSecret: amazonClientSecret,
      amazonRefreshToken: amazonRefreshToken,
      hasRedis: redisUrl != null,
      hasObjectStorage:
          r2AccessKeyId != null &&
          r2SecretAccessKey != null &&
          r2Bucket != null,
      hasAiProvider: anthropicApiKey != null,
      hasPayments: stripeSecretKey != null,
      logLevel: LogLevel.parse(environment['LOG_LEVEL']),
      allowedOrigins: _parseOrigins(environment['CORS_ALLOWED_ORIGINS']),
      requestTimeout: Duration(
        seconds: _duration(environment, 'REQUEST_TIMEOUT_SECONDS', 30),
      ),
      maxBodyBytes: _int(environment, 'MAX_BODY_BYTES', 4 * 1024 * 1024),
      aiRateLimitCapacity: _int(environment, 'AI_RATE_LIMIT_CAPACITY', 10),
      aiRateLimitRefillPerSecond: _double(
        environment,
        'AI_RATE_LIMIT_REFILL_PER_SECOND',
        0.5,
      ),
      apiRateLimitCapacity: _int(environment, 'API_RATE_LIMIT_CAPACITY', 120),
      apiRateLimitRefillPerSecond: _double(
        environment,
        'API_RATE_LIMIT_REFILL_PER_SECOND',
        5,
      ),
      maxOperationsPerBatch: _int(environment, 'MAX_OPERATIONS_PER_BATCH', 200),
      defaultPageLimit: _int(environment, 'DEFAULT_PAGE_LIMIT', 50),
      maxPageLimit: _int(environment, 'MAX_PAGE_LIMIT', 200),
      jwksCacheTtl: Duration(seconds: _int(environment, 'JWKS_CACHE_TTL', 900)),
      purgeInterval: Duration(
        seconds: _int(
          environment,
          'LIMPID_PURGE_INTERVAL_SECONDS',
          defaultAccountPurgeInterval.inSeconds,
        ),
      ),
      relayHeartbeatInterval: Duration(
        seconds: _int(
          environment,
          'LIMPID_RELAY_HEARTBEAT_SECONDS',
          defaultRelayHeartbeatInterval.inSeconds,
        ),
      ),
      relayPresenceTimeout: Duration(
        seconds: _int(
          environment,
          'LIMPID_RELAY_PRESENCE_TIMEOUT_SECONDS',
          defaultRelayPresenceTimeout.inSeconds,
        ),
      ),
    );
  }

  /// The profile the API runs under.
  final LimpidProfile profile;

  /// The engine backing the persistence ports.
  final DatabaseDriver databaseDriver;

  /// The path of the SQLite file, relative to the working directory.
  final String sqlitePath;

  /// The Postgres connection string, `null` when the driver is SQLite.
  final String? databaseUrl;

  /// The TCP port the server listens on. `0` asks the operating system for an
  /// ephemeral port, which is what the test suite uses.
  final int port;

  /// The Supabase project URL, used to build the expected token issuer.
  final String supabaseUrl;

  /// The URL serving the JSON Web Key Set of the Supabase project.
  final String supabaseJwksUrl;

  /// The anonymous Supabase key, never used to sign anything.
  final String supabaseAnonKey;

  /// The key of the Supabase service role, used by the administration API.
  ///
  /// La clé du rôle de service donne l'accès complet au projet : elle est
  /// lue dans l'environnement, jamais écrite en clair, et elle ne sert
  /// qu'à effacer un compte de Supabase Auth.
  final String supabaseServiceRoleKey;

  /// Whether the administration API of Supabase is configured.
  ///
  /// Un poste de développement n'a pas de projet Supabase : la purge n'a
  /// alors aucun compte à effacer de là-bas.
  final bool hasAuthAdmin;

  /// The Redis connection string, `null` when Redis is not configured.
  final String? redisUrl;

  /// The Cloudflare R2 account identifier.
  final String r2AccountId;

  /// The R2 access key identifier.
  final String r2AccessKeyId;

  /// The R2 secret access key.
  final String r2SecretAccessKey;

  /// The R2 bucket holding the exported artefacts.
  final String r2Bucket;

  /// The R2 S3 compatible endpoint.
  final String r2Endpoint;

  /// The Anthropic API key used by the AI gateway.
  final String anthropicApiKey;

  /// The Stripe secret key used by the checkout route.
  final String stripeSecretKey;

  /// The signing secret of the Stripe webhook endpoint.
  ///
  /// The secret is optional in both profiles: a server that does not have
  /// it refuses the webhook deliveries cleanly, it does not refuse to
  /// start. The secret is never written in clear and never leaves the
  /// process.
  final String? stripeWebhookSecret;

  /// The identifiers of the Stripe events the webhook reacts to.
  ///
  /// The list is empty when the variable is absent: the webhook then
  /// handles every event of the subscription. A value that names no known
  /// event does not disable the webhook either.
  final List<String> stripeWebhookEvents;

  /// L'identifiant du client de l'intégration Amazon KDP.
  ///
  /// Il est lu dans l'environnement et n'est jamais écrit en clair : il ne
  /// sert qu'à la demande du jeton d'accès.
  final String? amazonClientId;

  /// Le secret du client de l'intégration Amazon KDP.
  ///
  /// Il n'est jamais journalé et ne quitte jamais le corps de la demande
  /// d'autorisation.
  final String? amazonClientSecret;

  /// Le jeton de renouvellement de l'intégration Amazon KDP.
  ///
  /// C'est la seule credential qui n'expire pas : le jeton d'accès en est
  /// dérivé et renouvelé.
  final String? amazonRefreshToken;

  /// Whether the Amazon KDP distribution is configured.
  ///
  /// Les trois identifiants de l'intégration doivent être là : un serveur
  /// qui n'en a pas répond un refus propre sur la route du dépôt, au lieu
  /// de faire tomber le serveur.
  bool get hasKdpDistribution =>
      amazonClientId != null &&
      amazonClientSecret != null &&
      amazonRefreshToken != null;

  /// Whether Redis is configured and can be reached.
  final bool hasRedis;

  /// Whether the remote object storage is configured.
  final bool hasObjectStorage;

  /// Whether the AI provider is configured.
  final bool hasAiProvider;

  /// Whether the payment provider is configured.
  final bool hasPayments;

  /// The minimum level of the emitted logs.
  final LogLevel logLevel;

  /// The origins allowed by the CORS middleware.
  final List<String> allowedOrigins;

  /// The time budget of a single request.
  final Duration requestTimeout;

  /// The maximum accepted request body size, in bytes.
  final int maxBodyBytes;

  /// The number of AI calls a single IP may burst.
  final int aiRateLimitCapacity;

  /// How many AI calls an IP regains per second.
  final double aiRateLimitRefillPerSecond;

  /// The number of calls a single caller may burst, on any route of the API.
  ///
  /// The bucket covers the whole API: an export rebuilds a whole book, a
  /// checkout creates a real payment session, un export des données
  /// personnelles relit tous les documents d'un auteur. Aucune de ces routes
  /// ne peut rester sans limite.
  final int apiRateLimitCapacity;

  /// How many calls a caller regains per second, on any route of the API.
  final double apiRateLimitRefillPerSecond;

  /// The maximum number of operations accepted in a single push.
  final int maxOperationsPerBatch;

  /// The page size used when the client does not ask for one.
  final int defaultPageLimit;

  /// The largest accepted page size.
  final int maxPageLimit;

  /// How long the JWKS keys stay cached in memory.
  final Duration jwksCacheTtl;

  /// The delay between two passes of the purge worker.
  ///
  /// The worker erases the data of the accounts whose deletion request has
  /// reached its deadline (D-19). A short delay purges sooner, a long one
  /// spares the database.
  final Duration purgeInterval;

  /// The delay between two beats of a connection of the real-time relay.
  ///
  /// The relay sends a `ping` to the clients that stayed silent, and the
  /// clients answer: the beat is what keeps the presence of a peer alive.
  final Duration relayHeartbeatInterval;

  /// The delay after which a silent connection of the relay is purged.
  ///
  /// The peer that stopped beating leaves the room, and the other peers are
  /// told that it is gone.
  final Duration relayPresenceTimeout;

  /// The issuer every Supabase token must declare.
  String get expectedIssuer => '$supabaseUrl/auth/v1';

  static String _required(
    Map<String, String> environment,
    String name, {
    String? fallback,
  }) {
    final String? value = environment[name];
    final String candidate = (value == null || value.trim().isEmpty)
        ? (fallback ?? '')
        : value.trim();
    if (candidate.isEmpty) {
      throw ConfigException(
        variable: name,
        message: 'La variable d\'environnement $name est obligatoire.',
      );
    }
    return candidate;
  }

  static String? _optional(Map<String, String> environment, String name) {
    final String? value = environment[name];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Reads the URL of a remote service.
  ///
  /// The URL is mandatory in the production profile; in the development
  /// profile it falls back to the unreachable placeholder.
  static String _serviceUrl(
    Map<String, String> environment,
    String name, {
    required bool strict,
  }) {
    final String? value = _optional(environment, name);
    if (value != null) {
      _requireAbsoluteUrl(value, name);
      return value;
    }
    if (strict) {
      throw ConfigException(
        variable: name,
        message: 'La variable d\'environnement $name est obligatoire.',
      );
    }
    return devPlaceholderUrl;
  }

  /// Reads the credential of a remote service.
  ///
  /// The credential is mandatory in the production profile; in the
  /// development profile it falls back to the placeholder.
  static String _serviceSecret(
    Map<String, String> environment,
    String name, {
    required bool strict,
  }) {
    final String? value = _optional(environment, name);
    if (value != null) return value;
    if (strict) {
      throw ConfigException(
        variable: name,
        message: 'La variable d\'environnement $name est obligatoire.',
      );
    }
    return devPlaceholderSecret;
  }

  static void _requireAbsoluteUrl(String value, String name) {
    final Uri? parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw ConfigException(
        variable: name,
        message:
            'La variable d\'environnement $name doit être une URL absolue.',
      );
    }
  }

  static List<String> _parseOrigins(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    final List<String> origins = raw
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    return List<String>.unmodifiable(origins);
  }

  /// Reads a list of names, separated by commas.
  ///
  /// The list is empty when the value is absent: the caller then applies its
  /// own default, and a missing variable never stops the server.
  static List<String> _parseList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    final List<String> values = raw
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    return List<String>.unmodifiable(values);
  }

  static int _int(Map<String, String> environment, String name, int fallback) {
    final String? raw = environment[name];
    if (raw == null || raw.trim().isEmpty) return fallback;
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw ConfigException(
        variable: name,
        message:
            'La variable d\'environnement $name doit être un entier '
            'strictement positif.',
      );
    }
    return parsed;
  }

  static double _double(
    Map<String, String> environment,
    String name,
    double fallback,
  ) {
    final String? raw = environment[name];
    if (raw == null || raw.trim().isEmpty) return fallback;
    final double? parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw ConfigException(
        variable: name,
        message:
            'La variable d\'environnement $name doit être un nombre '
            'strictement positif.',
      );
    }
    return parsed;
  }

  static int _duration(
    Map<String, String> environment,
    String name,
    int fallbackSeconds,
  ) {
    final int seconds = _int(environment, name, fallbackSeconds);
    return seconds;
  }
}
