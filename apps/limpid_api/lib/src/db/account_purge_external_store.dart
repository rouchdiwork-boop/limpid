/// The third parties holding the data of an account.
///
/// La purge efface les données de l'API, puis celles des tiers : le compte
/// dans Supabase Auth et les artefacts dans le stockage objet. Un compte n'est
/// déclaré purgé que lorsque les deux suppressions ont abouti.
enum AccountPurgeTarget {
  /// The account itself, in the authentication service.
  auth('auth'),

  /// The artefacts of the account, in the object storage.
  storage('storage');

  const AccountPurgeTarget(this.label);

  /// The technical name of the target, as written in the database.
  final String label;
}

/// The state of the artefacts of one account.
final class AccountArtifactState {
  /// Creates a state.
  const AccountArtifactState({
    required this.prefix,
    this.deletedAt,
    this.deletedCount = 0,
  });

  /// The prefix of the storage holding the artefacts.
  final String prefix;

  /// The moment the artefacts of the prefix were erased, `null` when they
  /// are still there.
  final DateTime? deletedAt;

  /// The number of objects erased under the prefix.
  final int deletedCount;

  /// Whether the artefacts of the prefix were erased.
  bool get isDeleted => deletedAt != null;
}

/// The state of the third party deletions of one account.
///
/// The state is what makes the purge resumable: a pass that fails halfway
/// leaves the state saying what was done and what was not, and the next
/// pass carries on where the previous one stopped.
final class AccountPurgeExternalState {
  /// Creates a state.
  const AccountPurgeExternalState({
    required this.userId,
    this.authDeletedAt,
    this.storageDeletedAt,
    this.deletedCount = 0,
    this.attempts = 0,
    this.lastError = '',
    this.artifacts = const <AccountArtifactState>[],
  });

  /// The account whose data is being erased.
  final String userId;

  /// The moment the account was erased from the authentication service,
  /// `null` when it is still there.
  final DateTime? authDeletedAt;

  /// The moment the artefacts were erased from the object storage, `null`
  /// when some of them are still there.
  final DateTime? storageDeletedAt;

  /// The number of artefacts erased from the object storage.
  final int deletedCount;

  /// The number of passes that tried to erase the account.
  final int attempts;

  /// The reason of the last failure.
  final String lastError;

  /// The artefacts of the account, by prefix.
  final List<AccountArtifactState> artifacts;

  /// Whether the account was erased from the authentication service.
  bool get isAuthDeleted => authDeletedAt != null;

  /// Whether the artefacts were erased from the object storage.
  bool get isStorageDeleted => storageDeletedAt != null;

  /// Whether every third party was erased.
  ///
  /// The account is only purged for good when this is true: a purge that
  /// left data behind is incomplete, and an incomplete purge must never be
  /// declared complete.
  bool get isComplete => isAuthDeleted && isStorageDeleted;
}

/// The persistence port of the deletions carried out outside the API.
///
/// The port records two things : l'état des suppressions des tiers, et la
/// liste des préfixes du stockage qui portent les artefacts du compte. La
/// liste est écrite **avant** l'effacement des données de l'API : les
/// projets qui portent ces préfixes disparaissent avec l'effacement, et la
/// passe suivante n'aurait plus aucun moyen de retrouver les artefacts.
abstract interface class AccountPurgeExternalStore {
  /// The state of the third party deletions of [userId].
  ///
  /// The state of an account that was never purged is empty: no deletion
  /// was tried, and nothing was erased.
  Future<AccountPurgeExternalState> stateOf({required String userId});

  /// The prefixes of the storage holding the artefacts of [userId].
  ///
  /// Les artefacts d'un compte vivent sous le préfixe de chacun de ses
  /// projets : le compte possède ses projets, et chaque projet porte ses
  /// exports. La liste est donc dérivée des projets du compte, au moment
  /// où ils existent encore.
  Future<List<String>> artifactPrefixesOf({required String userId});

  /// Records the prefixes holding the artefacts of [userId].
  ///
  /// The call is idempotent: a prefix already recorded keeps its state.
  Future<void> recordArtifacts({
    required String userId,
    required List<String> prefixes,
    required DateTime at,
  });

  /// Records that the artefacts of [prefix] were erased.
  ///
  /// [deletedCount] is the number of erased objects.
  Future<void> markArtifactDeleted({
    required String userId,
    required String prefix,
    required DateTime at,
    int deletedCount,
  });

  /// Records that the data of [target] was erased.
  ///
  /// [deletedCount] is the number of erased objects.
  Future<void> markTargetDeleted({
    required String userId,
    required AccountPurgeTarget target,
    required DateTime at,
    int deletedCount,
  });

  /// Records that a pass failed to erase the data of [target].
  ///
  /// The failure never erases a success: a target that was erased stays
  /// erased, whatever the next attempt does.
  Future<void> markFailure({
    required String userId,
    required AccountPurgeTarget target,
    required String error,
    required DateTime at,
  });
}
