import 'package:postgres/postgres.dart';

import 'two_factor_database.dart';

/// L'implémentation Postgres du port [TwoFactorDatabase].
///
/// Le secret partagé du compte est stocké en base32 et n'est jamais
/// journalisé ; les codes de récupération ne sont stockés que sous forme
/// d'empreinte.
final class PostgresTwoFactorDatabase implements TwoFactorDatabase {
  /// Crée un port sur le pool [pool].
  const PostgresTwoFactorDatabase(this._pool);

  final Pool<Object?> _pool;

  @override
  Future<TwoFactorRecord?> findByUserId(String userId) async {
    final Result result = await _pool.execute(
      'SELECT user_id, secret, is_enabled, created_at, enabled_at '
      'FROM two_factor WHERE user_id = \$1',
      parameters: <Object?>[userId],
    );
    if (result.isEmpty) return null;
    return _readRecord(result.first);
  }

  @override
  Future<void> savePendingSecret({
    required String userId,
    required String secret,
    required DateTime createdAt,
  }) async {
    await _pool.execute(
      'INSERT INTO two_factor '
      '(user_id, secret, is_enabled, created_at, enabled_at) '
      'VALUES (\$1, \$2, FALSE, \$3, NULL) '
      'ON CONFLICT (user_id) DO UPDATE '
      'SET secret = EXCLUDED.secret, is_enabled = FALSE, '
      'created_at = EXCLUDED.created_at, enabled_at = NULL',
      parameters: <Object?>[userId, secret, createdAt],
    );
  }

  @override
  Future<void> activate({
    required String userId,
    required DateTime enabledAt,
    required List<String> codeHashes,
  }) async {
    await _pool.runTx((Session session) async {
      await session.execute(
        'UPDATE two_factor SET is_enabled = TRUE, enabled_at = \$2 '
        'WHERE user_id = \$1',
        parameters: <Object?>[userId, enabledAt],
      );
      await session.execute(
        'DELETE FROM two_factor_recovery_codes WHERE user_id = \$1',
        parameters: <Object?>[userId],
      );
      for (final String hash in codeHashes) {
        await session.execute(
          'INSERT INTO two_factor_recovery_codes (user_id, code_hash, used_at) '
          'VALUES (\$1, \$2, NULL)',
          parameters: <Object?>[userId, hash],
        );
      }
    });
  }

  @override
  Future<void> disable({required String userId}) async {
    await _pool.runTx((Session session) async {
      await session.execute(
        'DELETE FROM two_factor_recovery_codes WHERE user_id = \$1',
        parameters: <Object?>[userId],
      );
      await session.execute(
        'DELETE FROM two_factor WHERE user_id = \$1',
        parameters: <Object?>[userId],
      );
    });
  }

  @override
  Future<List<RecoveryCode>> recoveryCodesOf(String userId) async {
    final Result result = await _pool.execute(
      'SELECT user_id, code_hash, used_at FROM two_factor_recovery_codes '
      'WHERE user_id = \$1',
      parameters: <Object?>[userId],
    );
    return result.map(_readRecoveryCode).toList(growable: false);
  }

  @override
  Future<bool> consumeRecoveryCode({
    required String userId,
    required String codeHash,
    required DateTime usedAt,
  }) async {
    final Result result = await _pool.execute(
      'UPDATE two_factor_recovery_codes SET used_at = \$3 '
      'WHERE user_id = \$1 AND code_hash = \$2 AND used_at IS NULL',
      parameters: <Object?>[userId, codeHash, usedAt],
    );
    return result.affectedRows > 0;
  }

  static TwoFactorRecord _readRecord(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return TwoFactorRecord(
      userId: columns['user_id']! as String,
      secret: columns['secret']! as String,
      isEnabled: columns['is_enabled']! as bool,
      createdAt: _readRequiredDate(columns['created_at']),
      enabledAt: _readDate(columns['enabled_at']),
    );
  }

  static RecoveryCode _readRecoveryCode(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return RecoveryCode(
      userId: columns['user_id']! as String,
      codeHash: columns['code_hash']! as String,
      usedAt: _readDate(columns['used_at']),
    );
  }

  /// Lit une date obligatoire.
  ///
  /// La colonne est `NOT NULL` : une valeur absente signale une base
  /// incohérente, pas une date manquante.
  static DateTime _readRequiredDate(Object? value) {
    return _readDate(value) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Lit une date, `null` quand la colonne est vide.
  ///
  /// Une colonne vide est `NULL`, pas l'epoch : une date absente ne doit
  /// pas se confondre avec le 1er janvier 1970.
  static DateTime? _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return null;
  }
}
