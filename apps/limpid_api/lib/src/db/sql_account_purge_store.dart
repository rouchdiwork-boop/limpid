import 'account_purge_store.dart';
import 'audit_entry.dart';

/// The store of the purge, backed by SQL.
///
/// The erase happens in a single transaction: the ledger of the purges and
/// the rows of the account disappear together, or nothing happens at all.
/// Every statement is parameterized: no value ever reaches the engine through
/// string concatenation.
final class SqlAccountPurgeStore implements AccountPurgeStore {
  /// Creates a store on top of [database].
  const SqlAccountPurgeStore(this._database);

  /// The SQL port of the store.
  final AccountPurgeDatabase _database;

  /// The statement that opens the ledger of the purges.
  ///
  /// The `ON CONFLICT` clause is the lock between two workers: the first one
  /// to write the row owns the purge, the second one writes nothing.
  static const String _ledgerInsert =
      'INSERT INTO account_purges '
      '(user_id, requested_at, scheduled_for, purged_at, purged_by) '
      'VALUES (?, ?, ?, ?, ?) ON CONFLICT (user_id) DO NOTHING';

  /// The condition that lets a statement erase the rows of the account.
  ///
  /// The row of the ledger is written by the transaction of the purge, with
  /// the exact moment of the purge. A purge that finds the account already
  /// purged keeps the moment of the first one: its statements touch nothing,
  /// and the rows written after the first purge survive.
  static const String _holdsLedger =
      'EXISTS (SELECT 1 FROM account_purges '
      'WHERE user_id = ? AND purged_at = ?)';

  /// The index of the statement that opens the ledger.
  static const int _ledger = 0;

  /// The index of the statement erasing the messages of the account.
  static const int _messages = 1;

  /// The index of the statement erasing the operations of the account.
  static const int _ownOperations = 2;

  /// The index of the statement erasing the operations of its books.
  static const int _bookOperations = 3;

  /// The index of the statement erasing the collaborations.
  static const int _collaborations = 4;

  /// The index of the statement erasing the projects.
  static const int _projects = 5;

  @override
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT id, user_id, action, target_type, target_id, metadata, ip, '
      'created_at FROM audit_log WHERE action = ? '
      'ORDER BY created_at ASC, id ASC LIMIT ?',
      <Object?>[action, limit],
    );
    return List<AuditEntry>.unmodifiable(rows.map(_readEntry));
  }

  @override
  Future<AccountPurgeOutcome> purge({
    required String userId,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) async {
    final List<int> counts = await _database.transaction(
      _statements(
        userId: userId,
        requestedAt: requestedAt,
        scheduledFor: scheduledFor,
        purgedAt: purgedAt,
        workerId: workerId,
      ),
    );
    return AccountPurgeOutcome(
      userId: userId,
      messagesDeleted: counts[_messages],
      operationsDeleted: counts[_ownOperations] + counts[_bookOperations],
      collaborationsDeleted: counts[_collaborations],
      projectsDeleted: counts[_projects],
      purged: counts[_ledger] > 0,
    );
  }

  /// The statements of the purge, in the order they are run.
  ///
  /// The projects are erased last: the statements before them read the
  /// projects of the account to know which operations belong to them.
  List<(String, List<Object?>)> _statements({
    required String userId,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) {
    final Object? stamp = _database.encodeTimestamp(purgedAt);
    return <(String, List<Object?>)>[
      (
        _ledgerInsert,
        <Object?>[
          userId,
          _database.encodeTimestamp(requestedAt),
          _database.encodeTimestamp(scheduledFor),
          stamp,
          workerId,
        ],
      ),
      (
        'DELETE FROM comments WHERE author_id = ? AND $_holdsLedger',
        <Object?>[userId, userId, stamp],
      ),
      (
        'DELETE FROM sync_ops WHERE author_id = ? AND $_holdsLedger',
        <Object?>[userId, userId, stamp],
      ),
      (
        'DELETE FROM sync_ops WHERE project_id IN '
            '(SELECT id FROM projects WHERE owner_id = ?) AND $_holdsLedger',
        <Object?>[userId, userId, stamp],
      ),
      (
        'DELETE FROM project_members WHERE user_id = ? AND $_holdsLedger',
        <Object?>[userId, userId, stamp],
      ),
      (
        'DELETE FROM projects WHERE owner_id = ? AND $_holdsLedger',
        <Object?>[userId, userId, stamp],
      ),
    ];
  }

  /// Reads an entry of the journal from its row.
  AuditEntry _readEntry(Map<String, Object?> row) {
    return AuditEntry(
      userId: _text(row, 'user_id'),
      action: _text(row, 'action'),
      targetType: _text(row, 'target_type'),
      targetId: _text(row, 'target_id'),
      metadata: _database.decodeJson(row['metadata']),
      ip: row['ip'] as String?,
      createdAt: _database.decodeTimestamp(row['created_at']),
    );
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }
}
