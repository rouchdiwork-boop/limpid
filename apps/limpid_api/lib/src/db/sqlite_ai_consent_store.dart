import 'package:sqlite3/sqlite3.dart';

import 'ai_consent_store.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// L'implémentation SQLite du port [AiConsentStore].
///
/// L'adaptateur est la traduction du port Postgres : mêmes requêtes, même
/// clé. Chaque requête est paramétrée : aucune valeur n'atteint jamais le
/// moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteAiConsentStore implements AiConsentStore {
  /// Crée un magasin sur la base [database].
  const SqliteAiConsentStore(this._database);

  /// La base des consentements.
  final SqliteDatabase _database;

  static const String _columns =
      'user_id, scope, provider, is_granted, granted_at, revoked_at';

  @override
  Future<AiConsentRecord?> find({
    required String userId,
    required String scope,
    required String provider,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM ai_consents '
        'WHERE user_id = ? AND scope = ? AND provider = ?',
        <Object?>[userId, scope, provider],
      );
      if (result.isEmpty) return null;
      return _readConsent(result.first);
    });
  }

  @override
  Future<void> save(AiConsentRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO ai_consents '
        '(user_id, scope, provider, is_granted, granted_at, revoked_at) '
        'VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(user_id, scope, provider) DO UPDATE SET '
        'is_granted = excluded.is_granted, '
        'granted_at = excluded.granted_at, '
        'revoked_at = excluded.revoked_at',
        <Object?>[
          record.userId,
          record.scope,
          record.provider,
          SqliteValues.encodeBoolean(record.isGranted),
          SqliteValues.encodeTimestamp(record.grantedAt),
          _encodeNullable(record.revokedAt),
        ],
      );
    });
  }

  /// Encode un horodatage qui peut être absent.
  static int? _encodeNullable(DateTime? value) {
    if (value == null) return null;
    return SqliteValues.encodeTimestamp(value);
  }

  /// Lit un consentement depuis une ligne.
  static AiConsentRecord _readConsent(Row row) {
    return AiConsentRecord(
      userId: row['user_id']! as String,
      scope: row['scope']! as String,
      provider: row['provider']! as String,
      isGranted: SqliteValues.decodeBoolean(row['is_granted']),
      grantedAt: SqliteValues.decodeTimestamp(row['granted_at']),
      revokedAt: SqliteValues.decodeNullableTimestamp(row['revoked_at']),
    );
  }
}
