/// L'état de la double authentification d'un compte.
///
/// Le secret n'est actif qu'après la confirmation d'un premier code : une
/// inscription interrompue laisse un compte utilisable.
final class TwoFactorRecord {
  /// Crée un enregistrement.
  const TwoFactorRecord({
    required this.userId,
    required this.secret,
    required this.isEnabled,
    required this.createdAt,
    this.enabledAt,
  });

  /// Le compte auquel l'enregistrement appartient.
  final String userId;

  /// Le secret partagé, encodé en base32.
  final String secret;

  /// Indique si la double authentification est active.
  final bool isEnabled;

  /// L'instant où le secret a été généré.
  final DateTime createdAt;

  /// L'instant où la double authentification a été activée.
  final DateTime? enabledAt;

  @override
  String toString() => 'TwoFactorRecord($userId, enabled: $isEnabled)';
}

/// Un code de récupération à usage unique.
///
/// Le code lui-même n'est jamais conservé : seule son empreinte est
/// enregistrée, pour qu'une fuite de la base ne donne aucun code
/// utilisable.
final class RecoveryCode {
  /// Crée un code de récupération.
  const RecoveryCode({
    required this.userId,
    required this.codeHash,
    this.usedAt,
  });

  /// Le compte auquel le code appartient.
  final String userId;

  /// L'empreinte du code.
  final String codeHash;

  /// L'instant où le code a été consommé, `null` quand il est intact.
  final DateTime? usedAt;

  /// Indique si le code a déjà servi.
  bool get isUsed => usedAt != null;

  @override
  String toString() => 'RecoveryCode($userId, used: $isUsed)';
}

/// Le port de persistance de la double authentification.
///
/// Le port porte le secret partagé du compte, son état d'activation et les
/// empreintes des codes de récupération. Il ne porte aucune règle
/// métier : celles-ci vivent dans le service.
abstract interface class TwoFactorDatabase {
  /// L'enregistrement du compte [userId], `null` quand il n'en a pas.
  Future<TwoFactorRecord?> findByUserId(String userId);

  /// Enregistre le secret [secret] du compte [userId], en attente de
  /// confirmation.
  ///
  /// L'enregistrement remplace le secret en attente du compte : une
  /// inscription recommencée repart de zéro. Le compte n'est jamais activé.
  Future<void> savePendingSecret({
    required String userId,
    required String secret,
    required DateTime createdAt,
  });

  /// Active la double authentification du compte [userId] et enregistre les
  /// empreintes de ses codes de récupération.
  ///
  /// L'activation et les codes sont écrits ensemble : un compte ne doit
  /// jamais avoir une double authentification active sans code de
  /// récupération.
  Future<void> activate({
    required String userId,
    required DateTime enabledAt,
    required List<String> codeHashes,
  });

  /// Désactive la double authentification du compte [userId].
  ///
  /// Le secret est effacé et les codes de récupération sont invalidés.
  Future<void> disable({required String userId});

  /// Les codes de récupération du compte [userId].
  Future<List<RecoveryCode>> recoveryCodesOf(String userId);

  /// Consomme le code de récupération [codeHash] du compte [userId].
  ///
  /// Renvoie `true` quand le code existait et n'avait pas encore servi.
  Future<bool> consumeRecoveryCode({
    required String userId,
    required String codeHash,
    required DateTime usedAt,
  });
}
