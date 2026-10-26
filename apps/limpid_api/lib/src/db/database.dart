import 'package:postgres/postgres.dart';

/// The maximum number of connections opened against Postgres.
const int defaultMaxConnections = 10;

/// Builds the connection pool of the API from a connection string.
///
/// The string follows the usual `postgres://user:password@host:port/database`
/// shape; the `sslmode` query parameter selects the TLS behaviour
/// (`disable`, `require` or `verify-full`).
Pool<Object?> createPool(
  String databaseUrl, {
  int maxConnections = defaultMaxConnections,
}) {
  final Uri uri = Uri.parse(databaseUrl);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError.value(
      databaseUrl,
      'databaseUrl',
      'Expected a postgres:// connection string',
    );
  }

  final List<String> credentials = uri.userInfo.split(':');
  final String username = credentials.isEmpty ? '' : credentials.first;
  final String password = credentials.length > 1
      ? credentials.sublist(1).join(':')
      : '';
  final List<String> segments = uri.pathSegments
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
  final String database = segments.isEmpty ? 'postgres' : segments.last;

  final Endpoint endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: database,
    username: username,
    password: password,
  );

  return Pool.withEndpoints(
    <Endpoint>[endpoint],
    settings: PoolSettings(
      maxConnectionCount: maxConnections,
      applicationName: 'limpid-api',
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 30),
      sslMode: _sslMode(uri.queryParameters['sslmode']),
    ),
  );
}

SslMode _sslMode(String? raw) {
  switch (raw) {
    case 'disable':
      return SslMode.disable;
    case 'verify-ca':
    case 'verify-full':
      return SslMode.verifyFull;
    case 'require':
    case 'prefer':
    default:
      return SslMode.require;
  }
}
