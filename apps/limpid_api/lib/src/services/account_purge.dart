import 'package:limpid_core/limpid_core.dart';

import '../auth/account_auth_deletion.dart';
import '../db/account_purge_external_store.dart';
import '../db/account_purge_store.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../logging/logger.dart';
import '../storage/object_storage.dart';
import 'account_deletion.dart';
import 'account_purge_third_parties.dart';

/// The action journaled when the data of an account is erased for good.
const String accountPurgedAction = 'account.purged';

/// The action journaled when a pass failed to erase the data of an account
/// outside the API.
///
/// The action is the trace of a purge that is not over: the account is still
/// marked as to be purged, and the next pass tries again.
const String accountPurgeIncompleteAction = 'account.purge.incomplete';

/// The number of deletion requests read in a single pass.
///
/// The pass is bounded: the worker never holds the whole journal in memory,
/// and the accounts that did not fit are read by the next pass.
const int accountPurgeBatchSize = 100;

/// An account whose data was erased for good.
final class PurgedAccount {
  /// Creates a purged account.
  const PurgedAccount({
    required this.userId,
    required this.outcome,
    required this.purgedAt,
  });

  /// The account whose data was erased.
  final String userId;

  /// What the purge erased.
  final AccountPurgeOutcome outcome;

  /// The moment of the purge.
  final DateTime purgedAt;
}

/// An account whose purge failed.
final class PurgeFailure {
  /// Creates a failure.
  const PurgeFailure({required this.userId, required this.reason});

  /// The account whose purge failed.
  final String userId;

  /// The reason of the failure.
  final String reason;
}

/// The result of a pass of the worker.
final class PurgeReport {
  /// Creates a report.
  const PurgeReport({
    required this.purged,
    required this.skipped,
    required this.failures,
    required this.startedAt,
    required this.finishedAt,
  });

  /// The accounts whose data was erased.
  ///
  /// Un compte n'apparaît ici que lorsque sa donnée a disparu de l'API, du
  /// service d'authentification et du stockage objet.
  final List<PurgedAccount> purged;

  /// The accounts that were already erased, and were left untouched.
  final List<String> skipped;

  /// The accounts whose purge failed.
  ///
  /// Une purge incomplète est une purge échouée : le compte reste marqué
  /// comme à purger, et la passe suivante réessaie.
  final List<PurgeFailure> failures;

  /// The moment the pass started.
  final DateTime startedAt;

  /// The moment the pass ended.
  final DateTime finishedAt;

  /// Whether the pass erased at least one account.
  bool get hasPurged => purged.isNotEmpty;

  /// Whether the pass failed on at least one account.
  bool get hasFailures => failures.isNotEmpty;
}

/// The worker erasing the data of the accounts whose deletion has expired.
///
/// The worker is the second half of the obligation of the RGPD (D-19): the
/// request of an author is journaled by [AccountDeletionService] and the
/// data of the account lives for thirty days; the worker erases it for good
/// on the thirtieth day, and leaves the audit trail intact.
///
/// A pass never fails as a whole: an account whose purge fails is reported,
/// and the worker carries on with the next account.
final class AccountPurgeService {
  /// Creates the worker.
  ///
  /// The [workerId] names the worker in the audit trail; it identifies the
  /// process that erased the data.
  ///
  /// The [external] store, the [auth] service and the [storage] erase the
  /// data of the account outside the API. They are optional: a worker built
  /// without them only empties the database of the API, and the log says it,
  /// because an account purged without them still lives in the
  /// authentication service and in the object storage.
  AccountPurgeService({
    required this.store,
    required this.audit,
    required this.logger,
    AccountPurgeExternalStore? external,
    AccountAuthDeletion? auth,
    ObjectStorageDeletion? storage,
    String? workerId,
  }) : thirdParties = external == null
           ? null
           : AccountPurgeThirdParties(
               external: external,
               auth: auth,
               storage: storage,
             ),
       workerId = workerId ?? _newWorkerId();

  /// The store erasing the data of the accounts.
  final AccountPurgeStore store;

  /// The audit journal.
  final AuditLog audit;

  /// The structured logger.
  final Logger logger;

  /// The erasure of the data of the accounts outside the API.
  ///
  /// The collaborator is `null` when the worker is built without the third
  /// parties: the worker then only empties the database of the API, and the
  /// data left in the third parties is not tracked.
  final AccountPurgeThirdParties? thirdParties;

  /// The name of the worker, written in the audit trail.
  final String workerId;

  /// Whether the worker already said that it erases nothing outside the API.
  ///
  /// The warning is written once : le worker passe toutes les heures, et un
  /// avertissement répété n'apprend rien de plus à l'exploitant.
  bool _externalWarningWritten = false;

  /// Performs one pass of the purge.
  ///
  /// The pass reads the deletion requests recorded in the audit journal and
  /// erases the data of the accounts whose deadline is reached: an account
  /// whose deadline has not passed, and an account that was never asked to
  /// be deleted, are never touched.
  ///
  /// The pass is idempotent: an account that was already erased is left
  /// untouched and is not reported twice.
  Future<PurgeReport> run(DateTime now) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final List<AuditEntry> requests = await store.journalEntries(
      action: accountDeletionRequestedAction,
      limit: accountPurgeBatchSize,
    );

    final List<PurgedAccount> purged = <PurgedAccount>[];
    final List<String> skipped = <String>[];
    final List<PurgeFailure> failures = <PurgeFailure>[];

    if (thirdParties == null && !_externalWarningWritten) {
      _externalWarningWritten = true;
      logger.warning('account.purge.external.absent', <String, Object?>{
        'worker_id': workerId,
      });
    }

    for (final AuditEntry entry in requests) {
      final AccountDeletion deletion = AccountDeletion.fromEntry(entry);
      if (deletion.scheduledFor.isAfter(now)) continue;
      await _purge(entry.userId, deletion, now, purged, skipped, failures);
    }

    return PurgeReport(
      purged: List<PurgedAccount>.unmodifiable(purged),
      skipped: List<String>.unmodifiable(skipped),
      failures: List<PurgeFailure>.unmodifiable(failures),
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
    );
  }

  /// Erases the data of one account and reports what happened.
  ///
  /// A failure is caught here: the account is reported and the pass carries
  /// on with the next one. The catch is large : un échec d'un tiers ou de la
  /// base est un échec de purge, jamais la fin du worker.
  Future<void> _purge(
    String userId,
    AccountDeletion deletion,
    DateTime now,
    List<PurgedAccount> purged,
    List<String> skipped,
    List<PurgeFailure> failures,
  ) async {
    try {
      if (thirdParties == null) {
        await _purgeApiData(userId, deletion, now, purged, skipped);
        return;
      }
      await _purgeEverywhere(userId, deletion, now, purged, skipped, failures);
    } on Object catch (error) {
      failures.add(PurgeFailure(userId: userId, reason: error.toString()));
      logger.warning('account.purge.failed', <String, Object?>{
        'user_id': userId,
        'error': error.toString(),
      });
    }
  }

  /// Erases the data of the account in the API only.
  ///
  /// The method is the path taken by a worker built without the third
  /// parties: it empties the database of the API and nothing else.
  Future<void> _purgeApiData(
    String userId,
    AccountDeletion deletion,
    DateTime now,
    List<PurgedAccount> purged,
    List<String> skipped,
  ) async {
    final AccountPurgeOutcome outcome = await store.purge(
      userId: userId,
      email: deletion.email,
      requestedAt: deletion.requestedAt,
      scheduledFor: deletion.scheduledFor,
      purgedAt: now,
      workerId: workerId,
    );
    if (!outcome.purged) {
      skipped.add(userId);
      return;
    }
    purged.add(PurgedAccount(userId: userId, outcome: outcome, purgedAt: now));
    await audit.record(_trail(userId, outcome, now));
  }

  /// Erases the data of the account in the API and in the third parties.
  ///
  /// The order is the one the RGPD demands: la donnée de l'API d'abord, les
  /// tiers ensuite, et le compte n'est déclaré purgé qu'une fois les deux
  /// faits. Une suppression qui échoue laisse la purge incomplète : le
  /// compte reste marqué comme à purger, et la passe suivante réessaie.
  Future<void> _purgeEverywhere(
    String userId,
    AccountDeletion deletion,
    DateTime now,
    List<PurgedAccount> purged,
    List<String> skipped,
    List<PurgeFailure> failures,
  ) async {
    final AccountPurgeThirdParties thirdParties = this.thirdParties!;
    final AccountPurgeExternalStore externalStore = thirdParties.external;
    final AccountPurgeExternalState state = await externalStore.stateOf(
      userId: userId,
    );
    if (state.isComplete) {
      // Une passe précédente a déjà tout effacé : aucun tiers n'est
      // appelé une seconde fois.
      //
      // La trace peut however manquer : si l'effacement a abouti mais que
      // l'écriture de l'audit a échoué après coup, le compte est effacé
      // et rien ne le prouve. La trace est donc écrite ici quand elle
      // manque, à partir de l'audit lui-même : c'est lui qui sait ce qu'il
      // a deja écrit.
      await _writeMissingTrail(userId, now);
      skipped.add(userId);
      return;
    }

    // Les préfixes sont écrits avant l'effacement : les projets qui les
    // portent disparaissent avec lui, et la passe suivante n'aurait plus
    // aucun moyen de retrouver les artefacts.
    final List<String> prefixes = state.artifacts.isEmpty
        ? await externalStore.artifactPrefixesOf(userId: userId)
        : state.artifacts
              .map((AccountArtifactState artifact) => artifact.prefix)
              .toList(growable: false);
    if (prefixes.isNotEmpty) {
      await externalStore.recordArtifacts(
        userId: userId,
        prefixes: prefixes,
        at: now,
      );
    }

    final AccountPurgeOutcome outcome = await store.purge(
      userId: userId,
      email: deletion.email,
      requestedAt: deletion.requestedAt,
      scheduledFor: deletion.scheduledFor,
      purgedAt: now,
      workerId: workerId,
    );

    final ThirdPartyErasure erasure = await thirdParties.erase(
      userId: userId,
      state: state,
      prefixes: prefixes,
      now: now,
    );

    if (!erasure.isComplete) {
      failures.add(
        PurgeFailure(userId: userId, reason: erasure.reasons.join(' | ')),
      );
      await audit.record(_incompleteTrail(userId, erasure.reasons, now));
      logger.warning('account.purge.incomplete', <String, Object?>{
        'user_id': userId,
        'worker_id': workerId,
        'failures': erasure.reasons.length,
      });
      return;
    }

    purged.add(PurgedAccount(userId: userId, outcome: outcome, purgedAt: now));
    await audit.record(
      _trail(userId, outcome, now, await externalStore.stateOf(userId: userId)),
    );
  }

  /// Ecrit la trace d'une purge qui a abouti mais dont la trace manque.
  ///
  /// Une purge efface des donnees : si la trace ne part pas, l'auteur
  /// n'a plus de preuve que sa suppression a eu lieu, et l'audit ne peut
  /// pas dire ce qui a ete efface. La trace est donc ecrite une seconde
  /// fois quand la premiere a echoue.
  Future<void> _writeMissingTrail(String userId, DateTime now) async {
    final List<AuditEntry> existing = await audit.entriesOf(
      userId: userId,
      limit: 1,
      action: accountPurgedAction,
    );
    if (existing.isNotEmpty) return;
    await audit.record(
      AuditEntry(
        userId: userId,
        action: accountPurgedAction,
        targetType: 'account',
        targetId: userId,
        metadata: <String, Object?>{
          'worker_id': workerId,
          'purged_at': now.toUtc().toIso8601String(),
          'trail_recovered': true,
        },
        createdAt: now,
      ),
    );
  }

  /// The entry of the audit trail describing a purge.
  ///
  /// The trail is what makes the purge auditable: it says what was erased,
  /// when, and by which worker. It carries the trace of the suppressions
  /// outside the API : le compte n'est déclaré purgé que lorsque les deux
  /// suppressions externes ont abouti.
  AuditEntry _trail(
    String userId,
    AccountPurgeOutcome outcome,
    DateTime now, [
    AccountPurgeExternalState? state,
  ]) {
    return AuditEntry(
      userId: userId,
      action: accountPurgedAction,
      targetType: 'account',
      targetId: userId,
      metadata: <String, Object?>{
        'projects_deleted': outcome.projectsDeleted,
        'operations_deleted': outcome.operationsDeleted,
        'collaborations_deleted': outcome.collaborationsDeleted,
        'messages_deleted': outcome.messagesDeleted,
        // Le nombre de lignes effacees dans **toutes** les tables
        // personnelles : la trace dit ce que la purge a reellement efface,
        // pas seulement ce qui etait visible avant le lot 7.
        'personal_rows_deleted': outcome.personalRowsDeleted,
        'worker_id': workerId,
        'purged_at': now.toUtc().toIso8601String(),
        'auth_deleted_at': state?.authDeletedAt?.toUtc().toIso8601String(),
        'storage_deleted_at': state?.storageDeletedAt
            ?.toUtc()
            .toIso8601String(),
        'artifacts_deleted': state?.deletedCount ?? 0,
        'auth_configured': thirdParties?.isAuthConfigured ?? false,
        'storage_configured': thirdParties?.isStorageConfigured ?? false,
      },
      createdAt: now,
    );
  }

  /// The entry of the audit trail describing a purge that is not over.
  AuditEntry _incompleteTrail(
    String userId,
    List<String> reasons,
    DateTime now,
  ) {
    return AuditEntry(
      userId: userId,
      action: accountPurgeIncompleteAction,
      targetType: 'account',
      targetId: userId,
      metadata: <String, Object?>{
        'reasons': List<String>.unmodifiable(reasons),
        'worker_id': workerId,
        'attempted_at': now.toUtc().toIso8601String(),
      },
      createdAt: now,
    );
  }

  /// The name of a worker that has just started.
  static String _newWorkerId() {
    final UlidGenerator ulid = UlidGenerator();
    return 'account-purge-${ulid.generate().value}';
  }
}
