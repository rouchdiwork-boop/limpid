import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'audit_entry.dart';
import 'audit_log.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// The SQLite implementation of [AuditLog].
///
/// The journal is append only: the API writes an entry and never updates or
/// deletes one. It is read back for the export of the personal data and for
/// the state of the pending account deletions.
final class SqliteAuditLog implements AuditLog {
  /// Creates a journal on top of [database].
  const SqliteAuditLog(this._database);

  final SqliteDatabase _database;

  static final UlidGenerator _ulid = UlidGenerator();

  @override
  Future<void> record(AuditEntry entry) async {
    final DateTime createdAt = entry.createdAt ?? DateTime.now().toUtc();
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO audit_log '
        '(id, user_id, action, target_type, target_id, metadata, ip, '
        'created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          _ulid.generate().value,
          entry.userId,
          entry.action,
          entry.targetType,
          entry.targetId,
          SqliteValues.encodeJson(entry.metadata),
          entry.ip,
          SqliteValues.encodeTimestamp(createdAt),
        ],
      );
    });
  }

  @override
  Future<List<AuditEntry>> entriesOf({
    required String userId,
    required int limit,
    String? action,
  }) async {
    final List<Object?> parameters = <Object?>[userId];
    final StringBuffer where = StringBuffer(' WHERE user_id = ?');
    if (action != null) {
      where.write(' AND action = ?');
      parameters.add(action);
    }
    parameters.add(limit);

    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT id, user_id, action, target_type, target_id, metadata, ip, '
        'created_at FROM audit_log$where '
        'ORDER BY created_at DESC, id DESC LIMIT ?',
        parameters,
      );
      return result.map(_readEntry).toList(growable: false);
    });
  }

  static AuditEntry _readEntry(Row row) {
    return AuditEntry(
      userId: row['user_id']! as String,
      action: row['action']! as String,
      targetType: row['target_type']! as String,
      targetId: row['target_id']! as String,
      metadata: SqliteValues.decodeJson(row['metadata']),
      ip: row['ip'] as String?,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }
}
