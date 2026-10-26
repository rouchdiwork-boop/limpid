import 'dart:convert';

import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';

import 'audit_entry.dart';
import 'audit_log.dart';

/// The Postgres implementation of [AuditLog].
///
/// The journal is append only: the API writes an entry and never updates or
/// deletes one. It is read back for the export of the personal data and for
/// the state of the pending account deletions.
final class PostgresAuditLog implements AuditLog {
  /// Creates a journal on top of [pool].
  const PostgresAuditLog(this._pool);

  final Pool<Object?> _pool;

  static final UlidGenerator _ulid = UlidGenerator();

  @override
  Future<void> record(AuditEntry entry) async {
    await _pool.execute(
      'INSERT INTO audit_log '
      '(id, user_id, action, target_type, target_id, metadata, ip, created_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, COALESCE(\$8, now()))',
      parameters: <Object?>[
        _ulid.generate().value,
        entry.userId,
        entry.action,
        entry.targetType,
        entry.targetId,
        TypedValue(Type.jsonb, entry.metadata),
        entry.ip,
        entry.createdAt,
      ],
    );
  }

  @override
  Future<List<AuditEntry>> entriesOf({
    required String userId,
    required int limit,
    String? action,
  }) async {
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = \$1');
    if (action != null) {
      where.write(' AND action = \$2');
      parameters.add(action);
    }
    parameters.add(limit);
    final String limitParameter = '\$${parameters.length}';

    final Result result = await _pool.execute(
      'SELECT user_id, action, target_type, target_id, metadata, ip, '
      'created_at FROM audit_log$where '
      'ORDER BY created_at DESC, id DESC LIMIT $limitParameter',
      parameters: parameters,
    );
    return result.map(_readEntry).toList(growable: false);
  }

  static AuditEntry _readEntry(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return AuditEntry(
      userId: columns['user_id']! as String,
      action: columns['action']! as String,
      targetType: columns['target_type']! as String,
      targetId: columns['target_id']! as String,
      metadata: _readMetadata(columns['metadata']),
      ip: columns['ip'] as String?,
      createdAt: _readDate(columns['created_at']),
    );
  }

  static Map<String, dynamic> _readMetadata(Object? metadata) {
    if (metadata is Map<String, dynamic>) return metadata;
    if (metadata is String) {
      final Object? decoded = jsonDecode(metadata);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const <String, dynamic>{};
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
