import '../storage/artifact_keys.dart';
import 'account_purge_external_store.dart';
import 'account_purge_store.dart';

/// The store of the third party deletions, backed by SQL.
///
/// The store writes two tables : `account_purge_deletions` carries the state
/// of each target (the authentication service, the object storage), and
/// `account_purge_artifacts` carries the prefixes holding the artefacts of
/// the account and the moment they were erased.
///
/// Every statement is parameterized: no value ever reaches the engine
/// through string concatenation.
final class SqlAccountPurgeExternalStore implements AccountPurgeExternalStore {
  /// Creates a store on top of [database].
  const SqlAccountPurgeExternalStore(this._database);

  /// The SQL port of the store.
  final AccountPurgeDatabase _database;

  /// The statement inserting the state of a target.
  static const String _insertDeletion =
      'INSERT INTO account_purge_deletions '
      '(user_id, target, deleted_at, deleted_count, attempts, last_error, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (user_id, target) DO UPDATE SET '
      'deleted_at = excluded.deleted_at, '
      'deleted_count = excluded.deleted_count, '
      'updated_at = excluded.updated_at';

  /// The statement recording the failure of a target.
  static const String _insertFailure =
      'INSERT INTO account_purge_deletions '
      '(user_id, target, deleted_at, deleted_count, attempts, last_error, '
      'updated_at) VALUES (?, ?, NULL, 0, 1, ?, ?) '
      'ON CONFLICT (user_id, target) DO UPDATE SET '
      'attempts = account_purge_deletions.attempts + 1, '
      'last_error = excluded.last_error, '
      'updated_at = excluded.updated_at';

  /// The statement inserting a prefix of artefacts.
  static const String _insertArtifact =
      'INSERT INTO account_purge_artifacts '
      '(user_id, prefix, deleted_at, created_at) VALUES (?, ?, NULL, ?) '
      'ON CONFLICT (user_id, prefix) DO NOTHING';

  @override
  Future<AccountPurgeExternalState> stateOf({required String userId}) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT target, deleted_at, deleted_count, attempts, last_error '
      'FROM account_purge_deletions WHERE user_id = ?',
      <Object?>[userId],
    );
    final List<Map<String, Object?>> artifacts = await _database.query(
      'SELECT prefix, deleted_at, deleted_count FROM account_purge_artifacts '
      'WHERE user_id = ? ORDER BY prefix',
      <Object?>[userId],
    );

    DateTime? authDeletedAt;
    DateTime? storageDeletedAt;
    int attempts = 0;
    String lastError = '';

    for (final Map<String, Object?> row in rows) {
      final String target = _text(row, 'target');
      final DateTime? deletedAt = _database.decodeTimestamp(row['deleted_at']);
      if (target == AccountPurgeTarget.auth.label) {
        authDeletedAt = deletedAt;
      } else if (target == AccountPurgeTarget.storage.label) {
        storageDeletedAt = deletedAt;
      }
      attempts += _count(row, 'attempts');
      final String error = _text(row, 'last_error');
      if (error.isNotEmpty) lastError = error;
    }

    final List<AccountArtifactState> states = artifacts
        .map(
          (Map<String, Object?> row) => AccountArtifactState(
            prefix: _text(row, 'prefix'),
            deletedAt: _database.decodeTimestamp(row['deleted_at']),
            deletedCount: _count(row, 'deleted_count'),
          ),
        )
        .toList(growable: false);

    return AccountPurgeExternalState(
      userId: userId,
      authDeletedAt: authDeletedAt,
      storageDeletedAt: storageDeletedAt,
      deletedCount: states.fold<int>(
        0,
        (int total, AccountArtifactState artifact) =>
            total + artifact.deletedCount,
      ),
      attempts: attempts,
      lastError: lastError,
      artifacts: List<AccountArtifactState>.unmodifiable(states),
    );
  }

  @override
  Future<List<String>> artifactPrefixesOf({required String userId}) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT id FROM projects WHERE owner_id = ? ORDER BY id',
      <Object?>[userId],
    );
    return List<String>.unmodifiable(<String>[
      // L'archive RGPD du compte n'appartient a aucun livre : elle porte
      // le compte entier. Sans elle, les donnees personnelles survivraient
      // a la suppression du compte.
      ArtifactKeys.prefixOfAccount(userId),
      for (final Map<String, Object?> row in rows)
        ArtifactKeys.prefixOfProject(_text(row, 'id')),
    ]);
  }

  @override
  Future<void> recordArtifacts({
    required String userId,
    required List<String> prefixes,
    required DateTime at,
  }) async {
    if (prefixes.isEmpty) return;
    final Object? stamp = _database.encodeTimestamp(at);
    await _database.transaction(
      prefixes
          .map(
            (String prefix) =>
                (_insertArtifact, <Object?>[userId, prefix, stamp]),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> markArtifactDeleted({
    required String userId,
    required String prefix,
    required DateTime at,
    int deletedCount = 0,
  }) async {
    await _database.transaction(<(String, List<Object?>)>[
      (
        'UPDATE account_purge_artifacts SET deleted_at = ?, deleted_count = ? '
            'WHERE user_id = ? AND prefix = ?',
        <Object?>[_database.encodeTimestamp(at), deletedCount, userId, prefix],
      ),
    ]);
  }

  @override
  Future<void> markTargetDeleted({
    required String userId,
    required AccountPurgeTarget target,
    required DateTime at,
    int deletedCount = 0,
  }) async {
    final Object? stamp = _database.encodeTimestamp(at);
    await _database.transaction(<(String, List<Object?>)>[
      (
        _insertDeletion,
        <Object?>[userId, target.label, stamp, deletedCount, 0, '', stamp],
      ),
    ]);
  }

  @override
  Future<void> markFailure({
    required String userId,
    required AccountPurgeTarget target,
    required String error,
    required DateTime at,
  }) async {
    final Object? stamp = _database.encodeTimestamp(at);
    await _database.transaction(<(String, List<Object?>)>[
      (_insertFailure, <Object?>[userId, target.label, error, stamp]),
    ]);
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Reads a column of number, zero when it is missing.
  static int _count(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is int ? value : 0;
  }
}
