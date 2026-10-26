import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';

import 'audit_entry.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// The result of the purge of one account.
final class AccountPurgeOutcome {
  /// Creates an outcome.
  const AccountPurgeOutcome({
    required this.userId,
    required this.projectsDeleted,
    required this.operationsDeleted,
    required this.collaborationsDeleted,
    required this.messagesDeleted,
    required this.purged,
  });

  /// The account whose data was erased.
  final String userId;

  /// The number of projects of the account that were erased.
  final int projectsDeleted;

  /// The number of operations of the synchronisation journal that were
  /// erased.
  final int operationsDeleted;

  /// The number of collaborations of the account that were erased.
  final int collaborationsDeleted;

  /// The number of messages of the account that were erased.
  final int messagesDeleted;

  /// Whether this worker performed the purge.
  ///
  /// The purge is refused when the account was already purged: the ledger of
  /// the purges already holds its trace, and a second purge would change
  /// nothing.
  final bool purged;
}

/// The persistence port of the purge of the accounts.
///
/// The port crosses two tables: the journal of the audit, which holds the
/// deletion requests, and the ledger of the purges, which holds the accounts
/// that were erased. It never writes to the journal and never empties it:
/// the audit trail outlives the data it describes (D-19).
abstract interface class AccountPurgeStore {
  /// The entries of the audit journal carrying [action], the oldest first.
  ///
  /// The journal is the source of truth of the pending deletions: the
  /// request of an author is a mark in the audit trail, and the purge reads
  /// it to know which accounts must be emptied, and when.
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  });

  /// Erases the data of [userId] for good.
  ///
  /// The erase covers the projects the account owns, the operations of the
  /// synchronisation journal that belong to them, the rows of the
  /// collaborations and the personal data of the account itself. The
  /// operations of the account on a project of somebody else are erased too:
  /// they are the personal data of the author, not the manuscript of the
  /// co-author.
  ///
  /// The call is idempotent: an account that was already purged is left
  /// untouched, and the rows written after its purge survive.
  Future<AccountPurgeOutcome> purge({
    required String userId,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  });
}

/// The SQL port of the purge.
///
/// The dialect is confined to the adapters: SQLite and Postgres differ on
/// the placeholders, on the timestamps and on the JSON documents (D-29).
/// The SQL itself is written once, with the `?` placeholders of SQLite.
abstract interface class AccountPurgeDatabase {
  /// Rewrites the `?` placeholders of [sql] for the engine.
  String rewrite(String sql);

  /// Runs the query [sql] and returns its rows.
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args);

  /// Runs [statements] in a single transaction.
  ///
  /// The method answers the number of rows each statement touched, in the
  /// order of the statements: the purge reads it to report what it erased.
  Future<List<int>> transaction(List<(String, List<Object?>)> statements);

  /// Encodes a timestamp for the engine.
  Object? encodeTimestamp(DateTime? value);

  /// Decodes a timestamp read from the engine.
  DateTime? decodeTimestamp(Object? value);

  /// Decodes a JSON document read from the engine.
  Map<String, dynamic> decodeJson(Object? value);
}

/// The SQLite adapter of the purge.
///
/// The timestamps are the microseconds since the Unix epoch and the JSON
/// documents are textual: the convention of the SQLite dialect (see
/// `SqliteValues`).
final class SqliteAccountPurgeDatabase implements AccountPurgeDatabase {
  /// Creates an adapter on top of [database].
  const SqliteAccountPurgeDatabase(this._database);

  /// The database of the API.
  final SqliteDatabase _database;

  @override
  String rewrite(String sql) => sql;

  @override
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args) =>
      _database.run(() {
        final ResultSet result = _database.connection.select(sql, args);
        return result
            .map((Row row) => Map<String, Object?>.from(row))
            .toList(growable: false);
      });

  @override
  Future<List<int>> transaction(List<(String, List<Object?>)> statements) =>
      _database.transaction(() {
        final List<int> counts = <int>[];
        for (final (String sql, List<Object?> args) in statements) {
          _database.connection.execute(sql, args);
          counts.add(_database.connection.updatedRows);
        }
        return counts;
      });

  @override
  Object? encodeTimestamp(DateTime? value) =>
      value == null ? null : SqliteValues.encodeTimestamp(value);

  @override
  DateTime? decodeTimestamp(Object? value) =>
      value == null ? null : SqliteValues.decodeTimestamp(value);

  @override
  Map<String, dynamic> decodeJson(Object? value) =>
      SqliteValues.decodeJson(value);
}

/// The Postgres adapter of the purge.
///
/// The timestamps are sent as `TIMESTAMPTZ` and the JSON documents as
/// `JSONB`; the placeholders of the SQL are rewritten into the indexed form
/// of the protocol (`$1`, `$2`…).
final class PostgresAccountPurgeDatabase implements AccountPurgeDatabase {
  /// Creates an adapter on top of [pool].
  const PostgresAccountPurgeDatabase(this._pool);

  /// The pool of the API.
  final Pool<Object?> _pool;

  @override
  String rewrite(String sql) {
    var index = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (Match _) => '\$${++index}');
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> args,
  ) async {
    final Result result = await _pool.execute(rewrite(sql), parameters: args);
    return result
        .map((ResultRow row) => Map<String, Object?>.from(row.toColumnMap()))
        .toList(growable: false);
  }

  @override
  Future<List<int>> transaction(
    List<(String, List<Object?>)> statements,
  ) async {
    return _pool.runTx((TxSession session) async {
      final List<int> counts = <int>[];
      for (final (String sql, List<Object?> args) in statements) {
        final Result result = await session.execute(
          rewrite(sql),
          parameters: args,
        );
        counts.add(result.affectedRows);
      }
      return counts;
    });
  }

  @override
  Object? encodeTimestamp(DateTime? value) => value?.toUtc();

  @override
  DateTime? decodeTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }

  @override
  Map<String, dynamic> decodeJson(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const <String, dynamic>{};
  }
}
