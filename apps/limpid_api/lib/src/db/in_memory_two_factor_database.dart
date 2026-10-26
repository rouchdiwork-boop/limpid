import 'two_factor_database.dart';

/// L'implémentation en mémoire du port [TwoFactorDatabase].
///
/// Le port garde les mêmes invariants que les implémentations SQL : le
/// secret n'est actif qu'après l'activation, les codes de récupération ne
/// servent qu'une fois et la désactivation efface le secret et les codes.
final class InMemoryTwoFactorDatabase implements TwoFactorDatabase {
  /// Crée un port vide.
  InMemoryTwoFactorDatabase();

  /// Les enregistrements des comptes, par identifiant.
  final Map<String, TwoFactorRecord> _records = <String, TwoFactorRecord>{};

  /// Les codes de récupération des comptes, par identifiant.
  final Map<String, List<RecoveryCode>> _codes = <String, List<RecoveryCode>>{};

  @override
  Future<TwoFactorRecord?> findByUserId(String userId) async {
    return _records[userId];
  }

  @override
  Future<void> savePendingSecret({
    required String userId,
    required String secret,
    required DateTime createdAt,
  }) async {
    _records[userId] = TwoFactorRecord(
      userId: userId,
      secret: secret,
      isEnabled: false,
      createdAt: createdAt,
    );
    _codes.remove(userId);
  }

  @override
  Future<void> activate({
    required String userId,
    required DateTime enabledAt,
    required List<String> codeHashes,
  }) async {
    final TwoFactorRecord? existing = _records[userId];
    if (existing == null) return;
    _records[userId] = TwoFactorRecord(
      userId: existing.userId,
      secret: existing.secret,
      isEnabled: true,
      createdAt: existing.createdAt,
      enabledAt: enabledAt,
    );
    _codes[userId] = <RecoveryCode>[
      for (final String hash in codeHashes)
        RecoveryCode(userId: userId, codeHash: hash),
    ];
  }

  @override
  Future<void> disable({required String userId}) async {
    _records.remove(userId);
    _codes.remove(userId);
  }

  @override
  Future<List<RecoveryCode>> recoveryCodesOf(String userId) async {
    final List<RecoveryCode> codes = _codes[userId] ?? const <RecoveryCode>[];
    return List<RecoveryCode>.unmodifiable(codes);
  }

  @override
  Future<bool> consumeRecoveryCode({
    required String userId,
    required String codeHash,
    required DateTime usedAt,
  }) async {
    final List<RecoveryCode>? codes = _codes[userId];
    if (codes == null) return false;
    for (int index = 0; index < codes.length; index++) {
      final RecoveryCode code = codes[index];
      if (code.codeHash != codeHash || code.isUsed) continue;
      codes[index] = RecoveryCode(
        userId: code.userId,
        codeHash: code.codeHash,
        usedAt: usedAt,
      );
      return true;
    }
    return false;
  }
}
