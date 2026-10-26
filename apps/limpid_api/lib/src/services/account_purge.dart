import 'package:limpid_core/limpid_core.dart';

import '../db/account_purge_store.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../logging/logger.dart';
import 'account_deletion.dart';

/// The action journaled when the data of an account is erased for good.
const String accountPurgedAction = 'account.purged';

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
  final List<PurgedAccount> purged;

  /// The accounts that were already erased, and were left untouched.
  final List<String> skipped;

  /// The accounts whose purge failed.
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
  AccountPurgeService({
    required this.store,
    required this.audit,
    required this.logger,
    String? workerId,
  }) : workerId = workerId ?? _newWorkerId();

  /// The store erasing the data of the accounts.
  final AccountPurgeStore store;

  /// The audit journal.
  final AuditLog audit;

  /// The structured logger.
  final Logger logger;

  /// The name of the worker, written in the audit trail.
  final String workerId;

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
  /// on with the next one.
  Future<void> _purge(
    String userId,
    AccountDeletion deletion,
    DateTime now,
    List<PurgedAccount> purged,
    List<String> skipped,
    List<PurgeFailure> failures,
  ) async {
    try {
      final AccountPurgeOutcome outcome = await store.purge(
        userId: userId,
        requestedAt: deletion.requestedAt,
        scheduledFor: deletion.scheduledFor,
        purgedAt: now,
        workerId: workerId,
      );
      if (!outcome.purged) {
        skipped.add(userId);
        return;
      }
      purged.add(
        PurgedAccount(userId: userId, outcome: outcome, purgedAt: now),
      );
      await audit.record(_trail(userId, outcome, now));
    } on Exception catch (error) {
      failures.add(PurgeFailure(userId: userId, reason: error.toString()));
      logger.warning('account.purge.failed', <String, Object?>{
        'user_id': userId,
        'error': error.toString(),
      });
    }
  }

  /// The entry of the audit trail describing a purge.
  ///
  /// The trail is what makes the purge auditable: it says what was erased,
  /// when, and by which worker.
  AuditEntry _trail(String userId, AccountPurgeOutcome outcome, DateTime now) {
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
        'worker_id': workerId,
        'purged_at': now.toUtc().toIso8601String(),
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
