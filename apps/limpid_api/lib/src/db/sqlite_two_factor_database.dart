import 'package:sqlite3/sqlite3.dart';

import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'two_factor_database.dart';

/// L'implémentation SQLite du port [TwoFactorDatabase].
///
/// Le secret partagé du compte est stocké en base32 et n'est jamais
/// journalisé ; les codes de récupération ne sont stockés que sous forme
/// d'empreinte.
final class SqliteTwoFactorDatabase implements TwoFactorDatabase {
  /// Crée un port sur la base [database].
  const SqliteTwoFactorDatabase(this._database);

  final SqliteDatabase _database;

  @override
  Future<TwoFactorRecord?> findByUserId(String userId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT user_id, secret, is_enabled, created_at, enabled_at '
        'FROM two_factor WHERE user_id = ?',
        <Object?>[userId],
      );
      if (result.isEmpty) return null;
      return _readRecord(result.first);
    });
  }

  @override
  Future<void> savePendingSecret({
    required String userId,
    required String secret,
    required DateTime createdAt,
  }) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO two_factor '
        '(user_id, secret, is_enabled, created_at, enabled_at) '
        'VALUES (?, ?, 0, ?, NULL) '
        'ON CONFLICT(user_id) DO UPDATE SET '
        'secret = excluded.secret, is_enabled = 0, '
        'created_at = excluded.created_at, enabled_at = NULL',
        <Object?>[userId, secret, SqliteValues.encodeTimestamp(createdAt)],
      );
    });
  }

  @override
  Future<void> activate({
    required String userId,
    required DateTime enabledAt,
    required List<String> codeHashes,
  }) async {
    await _database.transaction(() {
      _database.connection.execute(
        'UPDATE two_factor SET is_enabled = 1, enabled_at = ? '
        'WHERE user_id = ?',
        <Object?>[SqliteValues.encodeTimestamp(enabledAt), userId],
      );
      _database.connection.execute(
        'DELETE FROM two_factor_recovery_codes WHERE user_id = ?',
        <Object?>[userId],
      );
      for (final String hash in codeHashes) {
        _database.connection.execute(
          'INSERT INTO two_factor_recovery_codes '
          '(user_id, code_hash, used_at) VALUES (?, ?, NULL)',
          <Object?>[userId, hash],
        );
      }
    });
  }

  @override
  Future<void> disable({required String userId}) async {
    await _database.transaction(() {
      _database.connection.execute(
        'DELETE FROM two_factor_recovery_codes WHERE user_id = ?',
        <Object?>[userId],
      );
      _database.connection.execute(
        'DELETE FROM two_factor WHERE user_id = ?',
        <Object?>[userId],
      );
    });
  }

  @override
  Future<List<RecoveryCode>> recoveryCodesOf(String userId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT user_id, code_hash, used_at '
        'FROM two_factor_recovery_codes WHERE user_id = ?',
        <Object?>[userId],
      );
      return result.map(_readRecoveryCode).toList(growable: false);
    });
  }

  @override
  Future<bool> consumeRecoveryCode({
    required String userId,
    required String codeHash,
    required DateTime usedAt,
  }) async {
    return _database.run(() {
      _database.connection.execute(
        'UPDATE two_factor_recovery_codes SET used_at = ? '
        'WHERE user_id = ? AND code_hash = ? AND used_at IS NULL',
        <Object?>[SqliteValues.encodeTimestamp(usedAt), userId, codeHash],
      );
      return _database.connection.updatedRows > 0;
    });
  }

  static TwoFactorRecord _readRecord(Row row) {
    return TwoFactorRecord(
      userId: row['user_id']! as String,
      secret: row['secret']! as String,
      isEnabled: SqliteValues.decodeBoolean(row['is_enabled']),
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      enabledAt: SqliteValues.decodeNullableTimestamp(row['enabled_at']),
    );
  }

  static RecoveryCode _readRecoveryCode(Row row) {
    return RecoveryCode(
      userId: row['user_id']! as String,
      codeHash: row['code_hash']! as String,
      usedAt: SqliteValues.decodeNullableTimestamp(row['used_at']),
    );
  }
}
