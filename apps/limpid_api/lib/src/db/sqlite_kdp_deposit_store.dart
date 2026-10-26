import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'kdp_deposit_record.dart';
import 'kdp_deposit_store.dart';
import 'kdp_record.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite des dépôts de dossiers Amazon KDP.
///
/// L'adaptateur est la traduction de celui de Postgres : mêmes requêtes,
/// même ordre de tri et mêmes invariants. Chaque requête est paramétrée :
/// aucune valeur n'atteint le moteur par concaténation.
///
/// La colonne JSON est un `TEXT` qui porte le document encodé, la convention
/// du dialecte SQLite. Les horodatages sont stockés en microsecondes depuis
/// l'époque Unix (voir `SqliteValues`).
final class SqliteKdpDepositStore implements KdpDepositStore {
  /// Crée une base sur [database].
  SqliteKdpDepositStore(this._database);

  final SqliteDatabase _database;

  static const String _columns =
      'id, publication_id, user_id, status, amazon_submission_id, issues, '
      'failure_reason, attempts, created_at, updated_at';

  @override
  Future<KdpDeposit?> findDeposit({
    required String depositId,
    required String userId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM kdp_deposits WHERE id = ? AND user_id = ?',
        <Object?>[depositId, userId],
      );
      return result.isEmpty ? null : _read(result.first);
    });
  }

  @override
  Future<KdpDeposit?> findDepositByPublication({
    required String publicationId,
    required String userId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM kdp_deposits '
        'WHERE publication_id = ? AND user_id = ?',
        <Object?>[publicationId, userId],
      );
      return result.isEmpty ? null : _read(result.first);
    });
  }

  @override
  Future<List<KdpDeposit>> listDeposits({required String userId}) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM kdp_deposits '
        'WHERE user_id = ? ORDER BY created_at DESC, id ASC',
        <Object?>[userId],
      );
      return List<KdpDeposit>.unmodifiable(
        result.map(_read).toList(growable: false),
      );
    });
  }

  @override
  Future<void> insertDeposit(KdpDeposit deposit) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO kdp_deposits ($_columns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        _parameters(deposit),
      );
    });
  }

  @override
  Future<void> updateDeposit(KdpDeposit deposit) async {
    await _database.run(() {
      _database.connection.execute(
        'UPDATE kdp_deposits SET status = ?, amazon_submission_id = ?, '
        'issues = ?, failure_reason = ?, attempts = ?, updated_at = ? '
        'WHERE id = ? AND user_id = ?',
        <Object?>[
          deposit.status.key,
          deposit.amazonSubmissionId,
          jsonEncode(_encodeIssues(deposit.issues)),
          deposit.failureReason,
          deposit.attempts,
          SqliteValues.encodeTimestamp(deposit.updatedAt),
          deposit.id,
          deposit.userId,
        ],
      );
      if (_database.connection.updatedRows == 0) {
        // La ligne n'existe pas ou appartient à un autre compte : la
        // mise à jour est refusée, elle n'est pas appliquée en silence.
        throw StateError(
          'The deposit ${deposit.id} does not belong to ${deposit.userId}.',
        );
      }
    });
  }

  @override
  Future<bool> updateDepositIfStatus(
    KdpDeposit deposit, {
    required KdpDepositStatus expectedStatus,
  }) async {
    return _database.run(() {
      _database.connection.execute(
        'UPDATE kdp_deposits SET status = ?, amazon_submission_id = ?, '
        'issues = ?, failure_reason = ?, attempts = ?, updated_at = ? '
        'WHERE id = ? AND user_id = ? AND status = ?',
        <Object?>[
          deposit.status.key,
          deposit.amazonSubmissionId,
          jsonEncode(_encodeIssues(deposit.issues)),
          deposit.failureReason,
          deposit.attempts,
          SqliteValues.encodeTimestamp(deposit.updatedAt),
          deposit.id,
          deposit.userId,
          expectedStatus.key,
        ],
      );
      return _database.connection.updatedRows > 0;
    });
  }

  static List<Object?> _parameters(KdpDeposit deposit) {
    return <Object?>[
      deposit.id,
      deposit.publicationId,
      deposit.userId,
      deposit.status.key,
      deposit.amazonSubmissionId,
      jsonEncode(_encodeIssues(deposit.issues)),
      deposit.failureReason,
      deposit.attempts,
      SqliteValues.encodeTimestamp(deposit.createdAt),
      SqliteValues.encodeTimestamp(deposit.updatedAt),
    ];
  }

  static KdpDeposit _read(Row row) {
    return KdpDeposit(
      id: row['id']! as String,
      publicationId: row['publication_id']! as String,
      userId: row['user_id']! as String,
      status: _readStatus(row['status']),
      amazonSubmissionId: row['amazon_submission_id'] as String?,
      issues: _readIssues(row['issues']),
      failureReason: row['failure_reason'] as String?,
      attempts: SqliteValues.decodeInt(row['attempts']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
    );
  }

  static List<Object?> _encodeIssues(List<KdpIssue> issues) {
    return <Object?>[for (final KdpIssue issue in issues) issue.toJson()];
  }

  static List<KdpIssue> _readIssues(Object? value) {
    final List<KdpIssue> issues = <KdpIssue>[];
    for (final Object? entry in _readList(value)) {
      final KdpIssue? issue = _readIssue(entry);
      if (issue != null) issues.add(issue);
    }
    return List<KdpIssue>.unmodifiable(issues);
  }

  static KdpIssue? _readIssue(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? code = value['code'];
    final Object? field = value['field'];
    final Object? message = value['message'];
    if (code is! String || field is! String || message is! String) {
      return null;
    }
    return KdpIssue(
      code: code,
      field: field,
      message: message,
      severity: _readSeverity(value['severity']),
    );
  }

  static KdpIssueSeverity _readSeverity(Object? value) {
    if (value is String) {
      for (final KdpIssueSeverity severity in KdpIssueSeverity.values) {
        if (severity.key == value) return severity;
      }
    }
    return KdpIssueSeverity.blocking;
  }

  static KdpDepositStatus _readStatus(Object? value) {
    for (final KdpDepositStatus status in KdpDepositStatus.values) {
      if (status.key == value) return status;
    }
    // Un état inconnu est traité comme une issue incertaine : il ne
    // relance rien, il se réconcilie.
    return KdpDepositStatus.unknown;
  }

  static List<Object?> _readList(Object? value) {
    if (value is List) return value.cast<Object?>();
    if (value is String) {
      try {
        final Object? decoded = jsonDecode(value);
        if (decoded is List) return decoded.cast<Object?>();
      } on FormatException {
        return const <Object?>[];
      }
    }
    return const <Object?>[];
  }
}
