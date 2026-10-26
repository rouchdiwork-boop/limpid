import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../http/pagination.dart';
import 'webhook_database.dart';
import 'webhook_record.dart';

/// L'implémentation Postgres du port [WebhookDatabase].
///
/// L'empreinte de la clé d'API et les secrets de signature sont stockés en
/// base : ils ne sont jamais journalisés et ne quittent la base que par la
/// réponse de création ou de rotation.
final class PostgresWebhookDatabase implements WebhookDatabase {
  /// Crée un port sur le pool [pool].
  const PostgresWebhookDatabase(this._pool);

  final Pool<Object?> _pool;

  static const String _keyColumns =
      'id, user_id, name, key_hash, scopes, is_active, created_at, '
      'rotated_at, revoked_at, last_used_at';

  static const String _endpointColumns =
      'id, user_id, url, events, secret, previous_secret, '
      'previous_secret_expires_at, is_active, created_at, updated_at';

  static const String _deliveryColumns =
      'id, endpoint_id, user_id, event, payload, status, http_status, '
      'error_message, attempts, created_at, completed_at';

  // ---------------------------------------------------------------------
  // Les clés d'API.
  // ---------------------------------------------------------------------

  @override
  Future<ApiKeyRecord?> findApiKey(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_keyColumns FROM api_keys WHERE id = \$1',
      parameters: <Object?>[id],
    );
    if (result.isEmpty) return null;
    return _readApiKey(result.first);
  }

  @override
  Future<ApiKeyRecord?> findApiKeyByHash(String keyHash) async {
    final Result result = await _pool.execute(
      'SELECT $_keyColumns FROM api_keys WHERE key_hash = \$1',
      parameters: <Object?>[keyHash],
    );
    if (result.isEmpty) return null;
    return _readApiKey(result.first);
  }

  @override
  Future<WebhookPage<ApiKeyRecord>> listApiKeys({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = \$1');

    if (decoded != null) {
      final DateTime createdAt = DateTime.parse(decoded.updatedAt).toUtc();
      where.write(' AND (created_at < \$2 OR (created_at = \$3 AND id > \$4))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final Result result = await _pool.execute(
      'SELECT $_keyColumns FROM api_keys$where '
      'ORDER BY created_at DESC, id ASC LIMIT \$${parameters.length}',
      parameters: parameters,
    );
    final List<ApiKeyRecord> rows = result
        .map(_readApiKey)
        .toList(growable: false);
    final bool hasMore = rows.length > limit;
    final List<ApiKeyRecord> items = hasMore ? rows.sublist(0, limit) : rows;
    final int total = await _count('api_keys', userId);
    return WebhookPage<ApiKeyRecord>(
      items: items,
      total: total,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              items.last.createdAt.toUtc().toIso8601String(),
              items.last.id,
            )
          : null,
    );
  }

  @override
  Future<void> insertApiKey(ApiKeyRecord record) async {
    await _pool.execute(
      'INSERT INTO api_keys '
      '(id, user_id, name, key_hash, scopes, is_active, created_at, '
      'rotated_at, revoked_at, last_used_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)',
      parameters: <Object?>[
        record.id,
        record.userId,
        record.name,
        record.keyHash,
        _encodeScopes(record.scopes),
        record.isActive,
        record.createdAt,
        record.rotatedAt,
        record.revokedAt,
        record.lastUsedAt,
      ],
    );
  }

  @override
  Future<void> updateApiKey(ApiKeyRecord record) async {
    await _pool.execute(
      'UPDATE api_keys SET name = \$2, key_hash = \$3, scopes = \$4, '
      'is_active = \$5, rotated_at = \$6, revoked_at = \$7, '
      'last_used_at = \$8 WHERE id = \$1',
      parameters: <Object?>[
        record.id,
        record.name,
        record.keyHash,
        _encodeScopes(record.scopes),
        record.isActive,
        record.rotatedAt,
        record.revokedAt,
        record.lastUsedAt,
      ],
    );
  }

  @override
  Future<void> deleteApiKey(String id) async {
    await _pool.execute(
      'DELETE FROM api_keys WHERE id = \$1',
      parameters: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------------
  // Les points de rappel.
  // ---------------------------------------------------------------------

  @override
  Future<WebhookEndpointRecord?> findEndpoint(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_endpointColumns FROM webhook_endpoints WHERE id = \$1',
      parameters: <Object?>[id],
    );
    if (result.isEmpty) return null;
    return _readEndpoint(result.first);
  }

  @override
  Future<WebhookPage<WebhookEndpointRecord>> listEndpoints({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = \$1');

    if (decoded != null) {
      final DateTime createdAt = DateTime.parse(decoded.updatedAt).toUtc();
      where.write(' AND (created_at < \$2 OR (created_at = \$3 AND id > \$4))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final Result result = await _pool.execute(
      'SELECT $_endpointColumns FROM webhook_endpoints$where '
      'ORDER BY created_at DESC, id ASC LIMIT \$${parameters.length}',
      parameters: parameters,
    );
    final List<WebhookEndpointRecord> rows = result
        .map(_readEndpoint)
        .toList(growable: false);
    final bool hasMore = rows.length > limit;
    final List<WebhookEndpointRecord> items = hasMore
        ? rows.sublist(0, limit)
        : rows;
    final int total = await _count('webhook_endpoints', userId);
    return WebhookPage<WebhookEndpointRecord>(
      items: items,
      total: total,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              items.last.createdAt.toUtc().toIso8601String(),
              items.last.id,
            )
          : null,
    );
  }

  @override
  Future<List<WebhookEndpointRecord>> listSubscribedEndpoints({
    required String userId,
    required String event,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_endpointColumns FROM webhook_endpoints '
      'WHERE user_id = \$1 AND is_active = TRUE',
      parameters: <Object?>[userId],
    );
    return result
        .map(_readEndpoint)
        .where(
          (WebhookEndpointRecord endpoint) => endpoint.events.contains(event),
        )
        .toList(growable: false);
  }

  @override
  Future<void> insertEndpoint(WebhookEndpointRecord endpoint) async {
    await _pool.execute(
      'INSERT INTO webhook_endpoints '
      '(id, user_id, url, events, secret, previous_secret, '
      'previous_secret_expires_at, is_active, created_at, updated_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)',
      parameters: <Object?>[
        endpoint.id,
        endpoint.userId,
        endpoint.url,
        _encodeScopes(endpoint.events),
        endpoint.secret,
        endpoint.previousSecret,
        endpoint.previousSecretExpiresAt,
        endpoint.isActive,
        endpoint.createdAt,
        endpoint.updatedAt,
      ],
    );
  }

  @override
  Future<void> updateEndpoint(WebhookEndpointRecord endpoint) async {
    await _pool.execute(
      'UPDATE webhook_endpoints SET url = \$2, events = \$3, secret = \$4, '
      'previous_secret = \$5, previous_secret_expires_at = \$6, '
      'is_active = \$7, updated_at = \$8 WHERE id = \$1',
      parameters: <Object?>[
        endpoint.id,
        endpoint.url,
        _encodeScopes(endpoint.events),
        endpoint.secret,
        endpoint.previousSecret,
        endpoint.previousSecretExpiresAt,
        endpoint.isActive,
        endpoint.updatedAt,
      ],
    );
  }

  @override
  Future<void> deleteEndpoint(String id) async {
    await _pool.execute(
      'DELETE FROM webhook_endpoints WHERE id = \$1',
      parameters: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------------
  // Le journal des livraisons.
  // ---------------------------------------------------------------------

  @override
  Future<WebhookDeliveryRecord?> findDelivery(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_deliveryColumns FROM webhook_deliveries WHERE id = \$1',
      parameters: <Object?>[id],
    );
    if (result.isEmpty) return null;
    return _readDelivery(result.first);
  }

  @override
  Future<WebhookPage<WebhookDeliveryRecord>> listDeliveries({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = \$1');

    if (decoded != null) {
      final DateTime createdAt = DateTime.parse(decoded.updatedAt).toUtc();
      where.write(' AND (created_at < \$2 OR (created_at = \$3 AND id > \$4))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final Result result = await _pool.execute(
      'SELECT $_deliveryColumns FROM webhook_deliveries$where '
      'ORDER BY created_at DESC, id ASC LIMIT \$${parameters.length}',
      parameters: parameters,
    );
    final List<WebhookDeliveryRecord> rows = result
        .map(_readDelivery)
        .toList(growable: false);
    final bool hasMore = rows.length > limit;
    final List<WebhookDeliveryRecord> items = hasMore
        ? rows.sublist(0, limit)
        : rows;
    final int total = await _count('webhook_deliveries', userId);
    return WebhookPage<WebhookDeliveryRecord>(
      items: items,
      total: total,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              items.last.createdAt.toUtc().toIso8601String(),
              items.last.id,
            )
          : null,
    );
  }

  @override
  Future<void> insertDelivery(WebhookDeliveryRecord delivery) async {
    await _pool.execute(
      'INSERT INTO webhook_deliveries '
      '(id, endpoint_id, user_id, event, payload, status, http_status, '
      'error_message, attempts, created_at, completed_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11)',
      parameters: <Object?>[
        delivery.id,
        delivery.endpointId,
        delivery.userId,
        delivery.event,
        delivery.payload,
        delivery.status.key,
        delivery.httpStatus,
        delivery.errorMessage,
        delivery.attempts,
        delivery.createdAt,
        delivery.completedAt,
      ],
    );
  }

  @override
  Future<void> updateDelivery(WebhookDeliveryRecord delivery) async {
    await _pool.execute(
      'UPDATE webhook_deliveries SET status = \$2, http_status = \$3, '
      'error_message = \$4, attempts = \$5, completed_at = \$6 WHERE id = \$1',
      parameters: <Object?>[
        delivery.id,
        delivery.status.key,
        delivery.httpStatus,
        delivery.errorMessage,
        delivery.attempts,
        delivery.completedAt,
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Les aides de lecture.
  // ---------------------------------------------------------------------

  Future<int> _count(String table, String userId) async {
    final Result result = await _pool.execute(
      'SELECT count(*) AS total FROM $table WHERE user_id = \$1',
      parameters: <Object?>[userId],
    );
    if (result.isEmpty) return 0;
    final Object? total = result.first.toColumnMap()['total'];
    return total is num ? total.toInt() : 0;
  }

  static String _encodeScopes(Set<String> values) {
    return jsonEncode(values.toList(growable: false)..sort());
  }

  static Set<String> _decodeScopes(Object? value) {
    if (value is! String) return const <String>{};
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! List<dynamic>) return const <String>{};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const <String>{};
    }
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static DateTime? _readNullableDate(Object? value) {
    if (value == null) return null;
    return _readDate(value);
  }

  static ApiKeyRecord _readApiKey(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return ApiKeyRecord(
      id: columns['id']! as String,
      userId: columns['user_id']! as String,
      name: columns['name']! as String,
      keyHash: columns['key_hash']! as String,
      scopes: _decodeScopes(columns['scopes']),
      isActive: columns['is_active']! as bool,
      createdAt: _readDate(columns['created_at']),
      rotatedAt: _readNullableDate(columns['rotated_at']),
      revokedAt: _readNullableDate(columns['revoked_at']),
      lastUsedAt: _readNullableDate(columns['last_used_at']),
    );
  }

  static WebhookEndpointRecord _readEndpoint(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return WebhookEndpointRecord(
      id: columns['id']! as String,
      userId: columns['user_id']! as String,
      url: columns['url']! as String,
      events: _decodeScopes(columns['events']),
      secret: columns['secret']! as String,
      previousSecret: columns['previous_secret'] as String?,
      previousSecretExpiresAt: _readNullableDate(
        columns['previous_secret_expires_at'],
      ),
      isActive: columns['is_active']! as bool,
      createdAt: _readDate(columns['created_at']),
      updatedAt: _readDate(columns['updated_at']),
    );
  }

  static WebhookDeliveryRecord _readDelivery(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final Object? attempts = columns['attempts'];
    return WebhookDeliveryRecord(
      id: columns['id']! as String,
      endpointId: columns['endpoint_id']! as String,
      userId: columns['user_id']! as String,
      event: columns['event']! as String,
      payload: columns['payload']! as String,
      status:
          WebhookDeliveryStatus.parse(columns['status']! as String) ??
          WebhookDeliveryStatus.failed,
      httpStatus: (columns['http_status'] as num?)?.toInt(),
      errorMessage: columns['error_message'] as String?,
      attempts: attempts is num ? attempts.toInt() : 0,
      createdAt: _readDate(columns['created_at']),
      completedAt: _readNullableDate(columns['completed_at']),
    );
  }
}
