import '../auth/account_auth_deletion.dart';
import '../db/account_purge_external_store.dart';
import '../storage/object_storage.dart';

/// The result of the erasure of an account outside the API.
final class ThirdPartyErasure {
  /// Creates a result.
  const ThirdPartyErasure({required this.reasons, this.deletedCount = 0});

  /// The reasons of the failures, empty when everything was erased.
  final List<String> reasons;

  /// The number of objects erased from the object storage.
  final int deletedCount;

  /// Whether every third party was erased.
  bool get isComplete => reasons.isEmpty;
}

/// The erasure of the data of an account outside the API.
///
/// La purge efface la donnée de l'API, puis celle des tiers : le compte dans
/// Supabase Auth et les artefacts dans le stockage objet. Un compte n'est
/// déclaré purgé que lorsque les deux suppressions ont abouti : une
/// suppression qui échoue laisse la purge incomplète, le compte reste marqué
/// comme à purger, et la passe suivante réessaie.
///
/// Le collaborateur se souvient de ce qu'il a fait : une cible déjà effacée
/// n'est plus appelée, et une passe qui reprend une purge interrompue
/// ne refait que ce qui reste.
final class AccountPurgeThirdParties {
  /// Creates the eraser.
  const AccountPurgeThirdParties({
    required this.external,
    this.auth,
    this.storage,
  });

  /// The store of the state of the deletions.
  final AccountPurgeExternalStore external;

  /// The service erasing the account from the authentication service.
  ///
  /// Le service est absent quand le poste n'a pas de projet Supabase : il
  /// n'y a alors aucun compte à effacer de là-bas.
  final AccountAuthDeletion? auth;

  /// The storage erasing the artefacts of the account.
  ///
  /// Le stockage est absent quand le poste n'a pas de bucket : il n'y a
  /// alors aucun artefact à effacer.
  final ObjectStorageDeletion? storage;

  /// Whether the authentication service is configured.
  bool get isAuthConfigured => auth?.isConfigured ?? false;

  /// Whether the object storage is configured.
  bool get isStorageConfigured => storage != null;

  /// Erases the account in the third parties and answers what failed.
  ///
  /// Les deux suppressions sont tentées l'une après l'autre : l'échec de
  /// l'une n'empêche pas l'autre d'aboutir, et la purge reste incomplète
  /// dès que l'une des deux échoue.
  Future<ThirdPartyErasure> erase({
    required String userId,
    required AccountPurgeExternalState state,
    required List<String> prefixes,
    required DateTime now,
  }) async {
    final List<String> reasons = <String>[];
    await _eraseAuthAccount(
      userId: userId,
      state: state,
      now: now,
      reasons: reasons,
    );
    final int deleted = await _eraseArtifacts(
      userId: userId,
      state: state,
      prefixes: prefixes,
      now: now,
      reasons: reasons,
    );
    return ThirdPartyErasure(
      reasons: List<String>.unmodifiable(reasons),
      deletedCount: deleted,
    );
  }

  /// Erases the account from the authentication service.
  Future<void> _eraseAuthAccount({
    required String userId,
    required AccountPurgeExternalState state,
    required DateTime now,
    required List<String> reasons,
  }) async {
    if (state.isAuthDeleted) return;
    try {
      if (isAuthConfigured) {
        await auth!.deleteAccount(userId: userId);
      }
      await external.markTargetDeleted(
        userId: userId,
        target: AccountPurgeTarget.auth,
        at: now,
        deletedCount: isAuthConfigured ? 1 : 0,
      );
    } on Object catch (error) {
      reasons.add('${AccountPurgeTarget.auth.label}: $error');
      await external.markFailure(
        userId: userId,
        target: AccountPurgeTarget.auth,
        error: error.toString(),
        at: now,
      );
    }
  }

  /// Erases the artefacts of the account from the object storage.
  ///
  /// Les préfixes sont effacés un par un : un préfixe qui échoue n'empêche
  /// pas les suivants d'être effacés, et la passe suivante ne réessaie que
  /// ceux qui restent.
  Future<int> _eraseArtifacts({
    required String userId,
    required AccountPurgeExternalState state,
    required List<String> prefixes,
    required DateTime now,
    required List<String> reasons,
  }) async {
    if (state.isStorageDeleted) return state.deletedCount;
    final Set<String> erased = state.artifacts
        .where((AccountArtifactState artifact) => artifact.isDeleted)
        .map((AccountArtifactState artifact) => artifact.prefix)
        .toSet();
    int deleted = state.deletedCount;
    bool failed = false;

    for (final String prefix in prefixes) {
      if (erased.contains(prefix)) continue;
      try {
        int count = 0;
        if (storage != null) {
          count = await storage!.deletePrefix(prefix: prefix);
        }
        deleted += count;
        await external.markArtifactDeleted(
          userId: userId,
          prefix: prefix,
          at: now,
          deletedCount: count,
        );
      } on Object catch (error) {
        failed = true;
        reasons.add('${AccountPurgeTarget.storage.label}: $error');
        await external.markFailure(
          userId: userId,
          target: AccountPurgeTarget.storage,
          error: error.toString(),
          at: now,
        );
      }
    }

    if (failed) return deleted;
    await external.markTargetDeleted(
      userId: userId,
      target: AccountPurgeTarget.storage,
      at: now,
      deletedCount: deleted,
    );
    return deleted;
  }
}
