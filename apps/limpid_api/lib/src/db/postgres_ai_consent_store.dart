import 'package:postgres/postgres.dart';

import 'ai_consent_store.dart';

/// L'implémentation Postgres du port [AiConsentStore].
///
/// La ligne porte la décision de l'auteur et les deux dates : la date du
/// dernier accord et la date du retrait. Elle ne porte **aucun texte** de
/// l'auteur : un consentement est une décision, pas une matière.
final class PostgresAiConsentStore implements AiConsentStore {
  /// Crée un magasin sur le pool [pool].
  const PostgresAiConsentStore(this._pool);

  /// Le pool de la base.
  final Pool<Object?> _pool;

  static const String _columns =
      'user_id, scope, provider, is_granted, granted_at, revoked_at';

  @override
  Future<AiConsentRecord?> find({
    required String userId,
    required String scope,
    required String provider,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM ai_consents '
      'WHERE user_id = \$1 AND scope = \$2 AND provider = \$3',
      parameters: <Object?>[userId, scope, provider],
    );
    if (result.isEmpty) return null;
    return _readConsent(result.first);
  }

  @override
  Future<void> save(AiConsentRecord record) async {
    await _pool.execute(
      'INSERT INTO ai_consents '
      '(user_id, scope, provider, is_granted, granted_at, revoked_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6) '
      'ON CONFLICT (user_id, scope, provider) DO UPDATE SET '
      'is_granted = EXCLUDED.is_granted, '
      'granted_at = EXCLUDED.granted_at, '
      'revoked_at = EXCLUDED.revoked_at',
      parameters: <Object?>[
        record.userId,
        record.scope,
        record.provider,
        record.isGranted,
        record.grantedAt,
        record.revokedAt,
      ],
    );
  }

  /// Lit un consentement depuis une ligne.
  static AiConsentRecord _readConsent(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return AiConsentRecord(
      userId: columns['user_id']! as String,
      scope: columns['scope']! as String,
      provider: columns['provider']! as String,
      isGranted: columns['is_granted']! as bool,
      grantedAt: _readDate(columns['granted_at']),
      revokedAt: _readNullableDate(columns['revoked_at']),
    );
  }

  /// Lit un horodatage.
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Lit un horodatage qui peut être absent.
  static DateTime? _readNullableDate(Object? value) {
    if (value == null) return null;
    return _readDate(value);
  }
}
