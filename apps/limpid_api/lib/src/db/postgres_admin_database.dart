import 'package:postgres/postgres.dart';

import '../http/pagination.dart';
import 'admin_database.dart';
import 'admin_plan_source.dart';
import 'audit_log.dart';
import 'feature_flag.dart';
import 'postgres_audit_log.dart';

/// The Postgres implementation of [AdminDatabase].
///
/// Every query is parameterized: no value ever reaches the server through
/// string concatenation. The identifiers of the tables and of the columns
/// of the formulas are constants of the adapter, never values coming from
/// a request.
final class PostgresAdminDatabase implements AdminDatabase {
  /// Creates a back-office on top of [pool].
  PostgresAdminDatabase(Pool<Object?> pool)
    : _pool = pool,
      _audit = PostgresAuditLog(pool);

  final Pool<Object?> _pool;
  final PostgresAuditLog _audit;

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
      final DateTime lastActivity = DateTime.parse(decoded.updatedAt);
      where.write(
        ' WHERE (last_activity_at < \$${parameters.length + 1} OR '
        '(last_activity_at = \$${parameters.length + 1} AND user_id > '
        '\$${parameters.length + 3}))',
      );
      parameters
        ..add(lastActivity)
        ..add(lastActivity)
        ..add(decoded.id);
    }
    parameters.add(limit + 1);
    final String limitParameter = '\$${parameters.length}';

    final Result result = await _pool.execute(
      'SELECT user_id, project_count, collaboration_count, comment_count, '
      'operation_count, last_activity_at FROM ($_usageSql) AS accounts'
      '$where ORDER BY last_activity_at DESC, user_id ASC '
      'LIMIT $limitParameter',
      parameters: parameters,
    );
    final List<AdminAccount> rows = result
        .map((ResultRow row) => _readAccount(row))
        .toList(growable: false);

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
    final Result result = await _pool.execute(
      'SELECT user_id, project_count, collaboration_count, comment_count, '
      'operation_count, last_activity_at FROM ($_usageSql) AS accounts '
      'WHERE user_id = \$1',
      parameters: <Object?>[userId],
    );
    if (result.isEmpty) return null;
    final List<AdminAccount> completed = await _complete(<AdminAccount>[
      _readAccount(result.first),
    ]);
    return completed.first;
  }

  @override
  Future<List<FeatureFlag>> listFeatureFlags() async {
    final Result result = await _pool.execute(
      'SELECT flag_key, is_enabled, description, updated_at, updated_by '
      'FROM feature_flags ORDER BY flag_key ASC',
    );
    return List<FeatureFlag>.unmodifiable(
      result.map((ResultRow row) => _readFlag(row)).toList(growable: false),
    );
  }

  @override
  Future<FeatureFlag?> findFeatureFlag(String key) async {
    final Result result = await _pool.execute(
      'SELECT flag_key, is_enabled, description, updated_at, updated_by '
      'FROM feature_flags WHERE flag_key = \$1',
      parameters: <Object?>[key],
    );
    return result.isEmpty ? null : _readFlag(result.first);
  }

  @override
  Future<FeatureFlag> setFeatureFlag({
    required String key,
    required bool isEnabled,
    required String? description,
    required String updatedBy,
  }) async {
    final Result result = await _pool.execute(
      'INSERT INTO feature_flags '
      '(flag_key, is_enabled, description, updated_at, updated_by) '
      'VALUES (\$1, \$2, COALESCE(\$3::text, \'\'), now(), \$4) '
      'ON CONFLICT (flag_key) DO UPDATE SET '
      'is_enabled = EXCLUDED.is_enabled, '
      'description = COALESCE(\$3::text, feature_flags.description), '
      'updated_at = now(), updated_by = EXCLUDED.updated_by '
      'RETURNING flag_key, is_enabled, description, updated_at, updated_by',
      parameters: <Object?>[key, isEnabled, description, updatedBy],
    );
    if (result.isEmpty) {
      throw StateError('The feature flag $key could not be written.');
    }
    return _readFlag(result.first);
  }

  /// The number of accounts the database knows.
  Future<int> _countAccounts() async {
    final Result result = await _pool.execute(
      'SELECT count(*) AS total FROM ('
      'SELECT owner_id AS user_id FROM projects WHERE deleted_at IS NULL '
      'UNION SELECT user_id FROM project_members '
      'UNION SELECT author_id FROM comments '
      'UNION SELECT author_id FROM sync_ops'
      ') AS accounts',
    );
    return result.isEmpty ? 0 : _readInt(result.first);
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
        select.write('\$${index + 1}');
      }
      select.write(')');

      final Result result = await _pool.execute(
        select.toString(),
        parameters: names,
      );

      final Map<String, String> found = <String, String>{};
      for (final ResultRow row in result) {
        final Map<String, dynamic> columns = row.toColumnMap();
        final Object? userId = columns[accountColumn];
        final Object? plan = columns[adminPlanColumn];
        if (userId is! String || plan is! String) continue;
        if (!isActiveAdminPlan(columns, hasStatus)) continue;
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
      select.write('\$${index + 1}');
    }
    select.write(')');

    final Result result = await _pool.execute(
      select.toString(),
      parameters: names,
    );
    return Set<String>.unmodifiable(
      result.map((ResultRow row) => row.toColumnMap()['user_id']! as String),
    );
  }

  /// The columns of [table], an empty set when the table does not exist.
  Future<Set<String>> _columnsOf(String table) async {
    final Result result = await _pool.execute(
      'SELECT column_name FROM information_schema.columns '
      'WHERE table_name = \$1',
      parameters: <Object?>[table],
    );
    return result
        .map((ResultRow row) => row.toColumnMap()['column_name']! as String)
        .toSet();
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

  static AdminAccount _readAccount(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return AdminAccount(
      userId: columns['user_id']! as String,
      plan: null,
      projectCount: _readIntOf(columns['project_count']),
      collaborationCount: _readIntOf(columns['collaboration_count']),
      commentCount: _readIntOf(columns['comment_count']),
      operationCount: _readIntOf(columns['operation_count']),
      lastActivityAt: _readDate(columns['last_activity_at']),
      isPurged: false,
    );
  }

  static FeatureFlag _readFlag(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return FeatureFlag(
      key: columns['flag_key']! as String,
      isEnabled: (columns['is_enabled'] as bool?) ?? false,
      description: (columns['description'] as String?) ?? '',
      updatedAt: _readDate(columns['updated_at']) ?? _epoch,
      updatedBy: (columns['updated_by'] as String?) ?? '',
    );
  }

  static int _readInt(ResultRow row) {
    return _readIntOf(row.toColumnMap()['total']);
  }

  static int _readIntOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
