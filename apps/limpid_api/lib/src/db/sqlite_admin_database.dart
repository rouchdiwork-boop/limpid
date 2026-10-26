import 'package:sqlite3/sqlite3.dart';

import '../http/pagination.dart';
import 'admin_database.dart';
import 'admin_plan_source.dart';
import 'audit_log.dart';
import 'feature_flag.dart';
import 'sqlite_audit_log.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// The SQLite implementation of [AdminDatabase].
///
/// The adapter is the translation of the Postgres one: same accounts, same
/// usage, same indicators and same audit trail. Every query is
/// parameterized: no value ever reaches the engine through string
/// concatenation.
///
/// The timestamps are stored as microseconds since the Unix epoch, the
/// convention of the SQLite dialect (see `SqliteValues`).
final class SqliteAdminDatabase implements AdminDatabase {
  /// Creates a back-office on top of [database].
  SqliteAdminDatabase(SqliteDatabase database)
    : _database = database,
      _audit = SqliteAuditLog(database);

  final SqliteDatabase _database;
  final SqliteAuditLog _audit;

  /// The accounts the database knows, with their usage.
  ///
  /// The accounts live in the identity provider: the API only knows the
  /// identifiers it met in its own tables. The rows are therefore the
  /// owners of the projects, the collaborators, the authors of the messages
  /// and the authors of the operations, deduplicated.
  static const String _usageSql = '''
WITH account_ids AS (
  SELECT owner_id AS user_id FROM projects WHERE deleted_at IS NULL
  UNION
  SELECT user_id FROM project_members
  UNION
  SELECT author_id FROM comments
  UNION
  SELECT author_id FROM sync_ops
),
account_usage AS (
  SELECT owner_id AS user_id, 'project' AS kind, COUNT(*) AS total,
         MAX(updated_at) AS last_at
    FROM projects WHERE deleted_at IS NULL GROUP BY owner_id
  UNION ALL
  SELECT user_id, 'collaboration', COUNT(*), MAX(created_at)
    FROM project_members GROUP BY user_id
  UNION ALL
  SELECT author_id, 'comment', COUNT(*), MAX(created_at)
    FROM comments GROUP BY author_id
  UNION ALL
  SELECT author_id, 'operation', COUNT(*), MAX(created_at)
    FROM sync_ops GROUP BY author_id
)
SELECT
  account_ids.user_id AS user_id,
  COALESCE(MAX(CASE WHEN account_usage.kind = 'project'
                    THEN account_usage.total END), 0) AS project_count,
  COALESCE(MAX(CASE WHEN account_usage.kind = 'collaboration'
                    THEN account_usage.total END), 0) AS collaboration_count,
  COALESCE(MAX(CASE WHEN account_usage.kind = 'comment'
                    THEN account_usage.total END), 0) AS comment_count,
  COALESCE(MAX(CASE WHEN account_usage.kind = 'operation'
                    THEN account_usage.total END), 0) AS operation_count,
  MAX(account_usage.last_at) AS last_activity_at
FROM account_ids
LEFT JOIN account_usage ON account_usage.user_id = account_ids.user_id
GROUP BY account_ids.user_id''';

  @override
  AuditLog get audit => _audit;

  @override
  Future<AccountPage> listAccounts({
    required int limit,
    required String? cursor,
  }) async {
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<Object?> parameters = <Object?>[];
    final StringBuffer where = StringBuffer();
    if (decoded != null) {
      final int lastActivity = SqliteValues.encodeTimestamp(
        DateTime.parse(decoded.updatedAt),
      );
      where.write(
        ' WHERE (last_activity_at < ? OR '
        '(last_activity_at = ? AND user_id > ?))',
      );
      parameters
        ..add(lastActivity)
        ..add(lastActivity)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);

    final List<AdminAccount> rows = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT user_id, project_count, collaboration_count, comment_count, '
        'operation_count, last_activity_at FROM ($_usageSql) AS accounts'
        '$where ORDER BY last_activity_at DESC, user_id ASC LIMIT ?',
        parameters,
      );
      return result.map(_readAccount).toList(growable: false);
    });

    final bool hasMore = rows.length > limit;
    final List<AdminAccount> page = hasMore ? rows.sublist(0, limit) : rows;
    final String? nextCursor = hasMore && page.isNotEmpty
        ? PageCursor.encode(_sortKeyOf(page.last), page.last.userId)
        : null;

    final int total = await _countAccounts();
    final List<AdminAccount> items = await _complete(page);

    return AccountPage(items: items, total: total, nextCursor: nextCursor);
  }

  @override
  Future<AdminAccount?> findAccount(String userId) async {
    final AdminAccount? account = await _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT user_id, project_count, collaboration_count, comment_count, '
        'operation_count, last_activity_at FROM ($_usageSql) AS accounts '
        'WHERE user_id = ?',
        <Object?>[userId],
      );
      return result.isEmpty ? null : _readAccount(result.first);
    });
    if (account == null) return null;
    final List<AdminAccount> completed = await _complete(<AdminAccount>[
      account,
    ]);
    return completed.first;
  }

  @override
  Future<List<FeatureFlag>> listFeatureFlags() async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT flag_key, is_enabled, description, updated_at, updated_by '
        'FROM feature_flags ORDER BY flag_key ASC',
      );
      return List<FeatureFlag>.unmodifiable(
        result.map(_readFlag).toList(growable: false),
      );
    });
  }

  @override
  Future<FeatureFlag?> findFeatureFlag(String key) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT flag_key, is_enabled, description, updated_at, updated_by '
        'FROM feature_flags WHERE flag_key = ?',
        <Object?>[key],
      );
      return result.isEmpty ? null : _readFlag(result.first);
    });
  }

  @override
  Future<FeatureFlag> setFeatureFlag({
    required String key,
    required bool isEnabled,
    required String? description,
    required String updatedBy,
  }) async {
    final int timestamp = SqliteValues.encodeTimestamp(DateTime.now().toUtc());
    final FeatureFlag stored = await _database.transaction(() {
      _database.connection.execute(
        'UPDATE feature_flags SET is_enabled = ?, '
        'description = COALESCE(?, description), updated_at = ?, '
        'updated_by = ? WHERE flag_key = ?',
        <Object?>[
          SqliteValues.encodeBoolean(isEnabled),
          description,
          timestamp,
          updatedBy,
          key,
        ],
      );
      if (_database.connection.updatedRows == 0) {
        _database.connection.execute(
          'INSERT INTO feature_flags '
          '(flag_key, is_enabled, description, updated_at, updated_by) '
          'VALUES (?, ?, ?, ?, ?)',
          <Object?>[
            key,
            SqliteValues.encodeBoolean(isEnabled),
            description ?? '',
            timestamp,
            updatedBy,
          ],
        );
      }
      final ResultSet result = _database.connection.select(
        'SELECT flag_key, is_enabled, description, updated_at, updated_by '
        'FROM feature_flags WHERE flag_key = ?',
        <Object?>[key],
      );
      return _readFlag(result.first);
    });
    return stored;
  }

  /// The number of accounts the database knows.
  Future<int> _countAccounts() async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT count(*) AS total FROM ('
        'SELECT owner_id AS user_id FROM projects WHERE deleted_at IS NULL '
        'UNION SELECT user_id FROM project_members '
        'UNION SELECT author_id FROM comments '
        'UNION SELECT author_id FROM sync_ops'
        ') AS accounts',
      );
      return result.isEmpty ? 0 : SqliteValues.decodeInt(result.first['total']);
    });
  }

  /// Completes the accounts with the formula and the state of the purge.
  Future<List<AdminAccount>> _complete(List<AdminAccount> accounts) async {
    if (accounts.isEmpty) return const <AdminAccount>[];
    final Set<String> userIds = accounts
        .map((AdminAccount account) => account.userId)
        .toSet();
    final Map<String, String> plans = await _plansOf(userIds);
    final Set<String> purged = await _purgedAmong(userIds);
    return List<AdminAccount>.unmodifiable(
      accounts.map(
        (AdminAccount account) => account.copyWith(
          plan: plans[account.userId],
          isPurged: purged.contains(account.userId),
        ),
      ),
    );
  }

  /// The formulas of the accounts, when the server knows them.
  ///
  /// The table of the formulas belongs to the module that owns the plans:
  /// the back-office reads it when it exists and when it carries the
  /// expected columns, and ignores it otherwise.
  Future<Map<String, String>> _plansOf(Set<String> userIds) async {
    if (userIds.isEmpty) return const <String, String>{};
    final Map<String, String> plans = <String, String>{};
    for (final String table in adminPlanTables) {
      final Set<String> columns = await _columnsOf(table);
      final String? accountColumn = adminPlanAccountColumnOf(columns);
      if (accountColumn == null || !columns.contains(adminPlanColumn)) {
        continue;
      }
      final bool hasStatus = columns.contains(adminPlanStatusColumn);
      final List<String> names = userIds.toList(growable: false);
      final StringBuffer select = StringBuffer()
        ..write('SELECT $accountColumn, $adminPlanColumn');
      if (hasStatus) select.write(', $adminPlanStatusColumn');
      select.write(' FROM $table WHERE $accountColumn IN (');
      for (int index = 0; index < names.length; index++) {
        if (index > 0) select.write(', ');
        select.write('?');
      }
      select.write(')');

      final List<Map<String, Object?>> rows = await _database.run(() {
        final ResultSet result = _database.connection.select(
          select.toString(),
          names,
        );
        return result
            .map((Row row) => Map<String, Object?>.from(row))
            .toList(growable: false);
      });

      final Map<String, String> found = <String, String>{};
      for (final Map<String, Object?> row in rows) {
        final Object? userId = row[accountColumn];
        final Object? plan = row[adminPlanColumn];
        if (userId is! String || plan is! String) continue;
        if (!isActiveAdminPlan(row, hasStatus)) continue;
        found[userId] = plan;
      }
      for (final MapEntry<String, String> entry in found.entries) {
        plans.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return Map<String, String>.unmodifiable(plans);
  }

  /// The accounts whose data was erased, among [userIds].
  Future<Set<String>> _purgedAmong(Set<String> userIds) async {
    if (userIds.isEmpty) return const <String>{};
    final List<String> names = userIds.toList(growable: false);
    final StringBuffer select = StringBuffer(
      'SELECT user_id FROM account_purges WHERE user_id IN (',
    );
    for (int index = 0; index < names.length; index++) {
      if (index > 0) select.write(', ');
      select.write('?');
    }
    select.write(')');

    final List<String> purged = await _database.run(() {
      final ResultSet result = _database.connection.select(
        select.toString(),
        names,
      );
      return result
          .map((Row row) => row['user_id']! as String)
          .toList(growable: false);
    });
    return Set<String>.unmodifiable(purged);
  }

  /// The columns of [table], an empty set when the table does not exist.
  Future<Set<String>> _columnsOf(String table) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'PRAGMA table_info($table)',
      );
      return result.map((Row row) => row['name']! as String).toSet();
    });
  }

  /// The sort key of an account, the epoch when it has no activity.
  static String _sortKeyOf(AdminAccount account) {
    return (account.lastActivityAt ?? _epoch).toUtc().toIso8601String();
  }

  /// The moment the accounts without activity are sorted on.
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  static AdminAccount _readAccount(Row row) {
    return AdminAccount(
      userId: row['user_id']! as String,
      plan: null,
      projectCount: SqliteValues.decodeInt(row['project_count']),
      collaborationCount: SqliteValues.decodeInt(row['collaboration_count']),
      commentCount: SqliteValues.decodeInt(row['comment_count']),
      operationCount: SqliteValues.decodeInt(row['operation_count']),
      lastActivityAt: SqliteValues.decodeNullableTimestamp(
        row['last_activity_at'],
      ),
      isPurged: false,
    );
  }

  static FeatureFlag _readFlag(Row row) {
    return FeatureFlag(
      key: row['flag_key']! as String,
      isEnabled: SqliteValues.decodeBoolean(row['is_enabled']),
      description: (row['description'] as String?) ?? '',
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
      updatedBy: (row['updated_by'] as String?) ?? '',
    );
  }
}
