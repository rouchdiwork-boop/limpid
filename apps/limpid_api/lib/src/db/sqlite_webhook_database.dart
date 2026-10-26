import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../http/pagination.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'webhook_database.dart';
import 'webhook_record.dart';

/// L'implémentation SQLite du port [WebhookDatabase].
///
/// L'empreinte de la clé d'API et les secrets de signature sont stockés en
/// base : ils ne sont jamais journalisés et ne quittent la base que par la
/// réponse de création ou de rotation.
final class SqliteWebhookDatabase implements WebhookDatabase {
  /// Crée un port sur la base [database].
  const SqliteWebhookDatabase(this._database);

  final SqliteDatabase _database;

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
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_keyColumns FROM api_keys WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      return _readApiKey(result.first);
    });
  }

  @override
  Future<ApiKeyRecord?> findApiKeyByHash(String keyHash) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_keyColumns FROM api_keys WHERE key_hash = ?',
        <Object?>[keyHash],
      );
      if (result.isEmpty) return null;
      return _readApiKey(result.first);
    });
  }

  @override
  Future<WebhookPage<ApiKeyRecord>> listApiKeys({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = ?');

    if (decoded != null) {
      final int createdAt = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(' AND (created_at < ? OR (created_at = ? AND id > ?))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final List<ApiKeyRecord> rows = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_keyColumns FROM api_keys$where '
        'ORDER BY created_at DESC, id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readApiKey).toList(growable: false);
    });

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
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO api_keys '
        '(id, user_id, name, key_hash, scopes, is_active, created_at, '
        'rotated_at, revoked_at, last_used_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.id,
          record.userId,
          record.name,
          record.keyHash,
          _encodeScopes(record.scopes),
          SqliteValues.encodeBoolean(record.isActive),
          SqliteValues.encodeTimestamp(record.createdAt),
          _encodeNullable(record.rotatedAt),
          _encodeNullable(record.revokedAt),
          _encodeNullable(record.lastUsedAt),
        ],
      );
    });
  }

  @override
  Future<void> updateApiKey(ApiKeyRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE api_keys SET name = ?, key_hash = ?, scopes = ?, '
        'is_active = ?, rotated_at = ?, revoked_at = ?, last_used_at = ? '
        'WHERE id = ?',
        <Object?>[
          record.name,
          record.keyHash,
          _encodeScopes(record.scopes),
          SqliteValues.encodeBoolean(record.isActive),
          _encodeNullable(record.rotatedAt),
          _encodeNullable(record.revokedAt),
          _encodeNullable(record.lastUsedAt),
          record.id,
        ],
      );
    });
  }

  @override
  Future<void> deleteApiKey(String id) async {
    await _database.run(() {
      _database.connection.execute(
        'DELETE FROM api_keys WHERE id = ?',
        <Object?>[id],
      );
    });
  }

  // ---------------------------------------------------------------------
  // Les points de rappel.
  // ---------------------------------------------------------------------

  @override
  Future<WebhookEndpointRecord?> findEndpoint(String id) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_endpointColumns FROM webhook_endpoints WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      return _readEndpoint(result.first);
    });
  }

  @override
  Future<WebhookPage<WebhookEndpointRecord>> listEndpoints({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = ?');

    if (decoded != null) {
      final int createdAt = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(' AND (created_at < ? OR (created_at = ? AND id > ?))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final List<WebhookEndpointRecord> rows = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_endpointColumns FROM webhook_endpoints$where '
        'ORDER BY created_at DESC, id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readEndpoint).toList(growable: false);
    });

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
    final List<WebhookEndpointRecord> candidates = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_endpointColumns FROM webhook_endpoints '
        'WHERE user_id = ? AND is_active = 1',
        <Object?>[userId],
      );
      return result.map(_readEndpoint).toList(growable: false);
    });
    return candidates
        .where(
          (WebhookEndpointRecord endpoint) => endpoint.events.contains(event),
        )
        .toList(growable: false);
  }

  @override
  Future<void> insertEndpoint(WebhookEndpointRecord endpoint) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO webhook_endpoints '
        '(id, user_id, url, events, secret, previous_secret, '
        'previous_secret_expires_at, is_active, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          endpoint.id,
          endpoint.userId,
          endpoint.url,
          _encodeScopes(endpoint.events),
          endpoint.secret,
          endpoint.previousSecret,
          _encodeNullable(endpoint.previousSecretExpiresAt),
          SqliteValues.encodeBoolean(endpoint.isActive),
          SqliteValues.encodeTimestamp(endpoint.createdAt),
          SqliteValues.encodeTimestamp(endpoint.updatedAt),
        ],
      );
    });
  }

  @override
  Future<void> updateEndpoint(WebhookEndpointRecord endpoint) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE webhook_endpoints SET url = ?, events = ?, secret = ?, '
        'previous_secret = ?, previous_secret_expires_at = ?, '
        'is_active = ?, updated_at = ? WHERE id = ?',
        <Object?>[
          endpoint.url,
          _encodeScopes(endpoint.events),
          endpoint.secret,
          endpoint.previousSecret,
          _encodeNullable(endpoint.previousSecretExpiresAt),
          SqliteValues.encodeBoolean(endpoint.isActive),
          SqliteValues.encodeTimestamp(endpoint.updatedAt),
          endpoint.id,
        ],
      );
    });
  }

  @override
  Future<void> deleteEndpoint(String id) async {
    await _database.run(() {
      _database.connection.execute(
        'DELETE FROM webhook_endpoints WHERE id = ?',
        <Object?>[id],
      );
    });
  }

  // ---------------------------------------------------------------------
  // Le journal des livraisons.
  // ---------------------------------------------------------------------

  @override
  Future<WebhookDeliveryRecord?> findDelivery(String id) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_deliveryColumns FROM webhook_deliveries WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      return _readDelivery(result.first);
    });
  }

  @override
  Future<WebhookPage<WebhookDeliveryRecord>> listDeliveries({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = ?');

    if (decoded != null) {
      final int createdAt = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(' AND (created_at < ? OR (created_at = ? AND id > ?))');
      parameters
        ..add(createdAt)
        ..add(createdAt)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final List<WebhookDeliveryRecord> rows = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_deliveryColumns FROM webhook_deliveries$where '
        'ORDER BY created_at DESC, id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readDelivery).toList(growable: false);
    });

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
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO webhook_deliveries '
        '(id, endpoint_id, user_id, event, payload, status, http_status, '
        'error_message, attempts, created_at, completed_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          delivery.id,
          delivery.endpointId,
          delivery.userId,
          delivery.event,
          delivery.payload,
          delivery.status.key,
          delivery.httpStatus,
          delivery.errorMessage,
          delivery.attempts,
          SqliteValues.encodeTimestamp(delivery.createdAt),
          _encodeNullable(delivery.completedAt),
        ],
      );
    });
  }

  @override
  Future<void> updateDelivery(WebhookDeliveryRecord delivery) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE webhook_deliveries SET status = ?, http_status = ?, '
        'error_message = ?, attempts = ?, completed_at = ? WHERE id = ?',
        <Object?>[
          delivery.status.key,
          delivery.httpStatus,
          delivery.errorMessage,
          delivery.attempts,
          _encodeNullable(delivery.completedAt),
          delivery.id,
        ],
      );
    });
  }

  // ---------------------------------------------------------------------
  // Les aides de lecture.
  // ---------------------------------------------------------------------

  Future<int> _count(String table, String userId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT count(*) AS total FROM $table WHERE user_id = ?',
        <Object?>[userId],
      );
      return result.isEmpty ? 0 : SqliteValues.decodeInt(result.first['total']);
    });
  }

  static int? _encodeNullable(DateTime? value) {
    if (value == null) return null;
    return SqliteValues.encodeTimestamp(value);
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

  static ApiKeyRecord _readApiKey(Row row) {
    return ApiKeyRecord(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      name: row['name']! as String,
      keyHash: row['key_hash']! as String,
      scopes: _decodeScopes(row['scopes']),
      isActive: SqliteValues.decodeBoolean(row['is_active']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      rotatedAt: SqliteValues.decodeNullableTimestamp(row['rotated_at']),
      revokedAt: SqliteValues.decodeNullableTimestamp(row['revoked_at']),
      lastUsedAt: SqliteValues.decodeNullableTimestamp(row['last_used_at']),
    );
  }

  static WebhookEndpointRecord _readEndpoint(Row row) {
    return WebhookEndpointRecord(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      url: row['url']! as String,
      events: _decodeScopes(row['events']),
      secret: row['secret']! as String,
      previousSecret: row['previous_secret'] as String?,
      previousSecretExpiresAt: SqliteValues.decodeNullableTimestamp(
        row['previous_secret_expires_at'],
      ),
      isActive: SqliteValues.decodeBoolean(row['is_active']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
    );
  }

  static WebhookDeliveryRecord _readDelivery(Row row) {
    return WebhookDeliveryRecord(
      id: row['id']! as String,
      endpointId: row['endpoint_id']! as String,
      userId: row['user_id']! as String,
      event: row['event']! as String,
      payload: row['payload']! as String,
      status:
          WebhookDeliveryStatus.parse(row['status']! as String) ??
          WebhookDeliveryStatus.failed,
      httpStatus: row['http_status'] as int?,
      errorMessage: row['error_message'] as String?,
      attempts: SqliteValues.decodeInt(row['attempts']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      completedAt: SqliteValues.decodeNullableTimestamp(row['completed_at']),
    );
  }
}
