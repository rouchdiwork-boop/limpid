import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'kdp_deposit_record.dart';
import 'kdp_deposit_store.dart';
import 'kdp_record.dart';

/// L'implémentation Postgres des dépôts de dossiers Amazon KDP.
///
/// Chaque requête est paramétrée : aucune valeur n'atteint le serveur par
/// concaténation. La colonne JSON (`issues`) est écrite en JSONB et relue
/// comme une liste.
final class PostgresKdpDepositStore implements KdpDepositStore {
  /// Crée une base sur [pool].
  PostgresKdpDepositStore(this._pool);

  final Pool<Object?> _pool;

  static const String _columns =
      'id, publication_id, user_id, status, amazon_submission_id, issues, '
      'failure_reason, attempts, created_at, updated_at';

  @override
  Future<KdpDeposit?> findDeposit({
    required String depositId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM kdp_deposits '
      'WHERE id = \$1 AND user_id = \$2',
      parameters: <Object?>[depositId, userId],
    );
    return result.isEmpty ? null : _read(result.first);
  }

  @override
  Future<KdpDeposit?> findDepositByPublication({
    required String publicationId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM kdp_deposits '
      'WHERE publication_id = \$1 AND user_id = \$2',
      parameters: <Object?>[publicationId, userId],
    );
    return result.isEmpty ? null : _read(result.first);
  }

  @override
  Future<List<KdpDeposit>> listDeposits({required String userId}) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM kdp_deposits '
      'WHERE user_id = \$1 ORDER BY created_at DESC, id ASC',
      parameters: <Object?>[userId],
    );
    return List<KdpDeposit>.unmodifiable(
      result.map(_read).toList(growable: false),
    );
  }

  @override
  Future<void> insertDeposit(KdpDeposit deposit) async {
    await _pool.execute(
      'INSERT INTO kdp_deposits ($_columns) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)',
      parameters: <Object?>[
        deposit.id,
        deposit.publicationId,
        deposit.userId,
        deposit.status.key,
        deposit.amazonSubmissionId,
        TypedValue(Type.jsonb, _encodeIssues(deposit.issues)),
        deposit.failureReason,
        deposit.attempts,
        deposit.createdAt,
        deposit.updatedAt,
      ],
    );
  }

  @override
  Future<void> updateDeposit(KdpDeposit deposit) async {
    final Result result = await _pool.execute(
      'UPDATE kdp_deposits SET status = \$1, amazon_submission_id = \$2, '
      'issues = \$3, failure_reason = \$4, attempts = \$5, updated_at = \$6 '
      'WHERE id = \$7 AND user_id = \$8',
      parameters: <Object?>[
        deposit.status.key,
        deposit.amazonSubmissionId,
        TypedValue(Type.jsonb, _encodeIssues(deposit.issues)),
        deposit.failureReason,
        deposit.attempts,
        deposit.updatedAt,
        deposit.id,
        deposit.userId,
      ],
    );
    if (result.affectedRows == 0) {
      // La ligne n'existe pas ou appartient à un autre compte : la mise à
      // jour est refusée, elle n'est pas appliquée en silence.
      throw StateError(
        'The deposit ${deposit.id} does not belong to ${deposit.userId}.',
      );
    }
  }

  @override
  Future<bool> updateDepositIfStatus(
    KdpDeposit deposit, {
    required KdpDepositStatus expectedStatus,
  }) async {
    final Result result = await _pool.execute(
      'UPDATE kdp_deposits SET status = \$1, amazon_submission_id = \$2, '
      'issues = \$3, failure_reason = \$4, attempts = \$5, updated_at = \$6 '
      'WHERE id = \$7 AND user_id = \$8 AND status = \$9',
      parameters: <Object?>[
        deposit.status.key,
        deposit.amazonSubmissionId,
        TypedValue(Type.jsonb, _encodeIssues(deposit.issues)),
        deposit.failureReason,
        deposit.attempts,
        deposit.updatedAt,
        deposit.id,
        deposit.userId,
        expectedStatus.key,
      ],
    );
    return result.affectedRows > 0;
  }

  static KdpDeposit _read(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return KdpDeposit(
      id: columns['id']! as String,
      publicationId: columns['publication_id']! as String,
      userId: columns['user_id']! as String,
      status: _readStatus(columns['status']),
      amazonSubmissionId: columns['amazon_submission_id'] as String?,
      issues: _readIssues(columns['issues']),
      failureReason: columns['failure_reason'] as String?,
      attempts: _readInt(columns['attempts']),
      createdAt: _readDate(columns['created_at']),
      updatedAt: _readDate(columns['updated_at']),
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

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
