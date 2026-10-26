import '../db/audit_entry.dart';
import '../db/audit_log.dart';

/// The number of days the account survives a deletion request (D-19).
///
/// The request never erases anything on the spot: the rows live for thirty
/// days, then the purge removes them for good.
const int accountDeletionRetentionDays = 30;

/// The action journaled when an author asks for the deletion of their
/// account.
const String accountDeletionRequestedAction = 'account.deletion_requested';

/// The number of entries read to find the pending deletion of an account.
const int accountDeletionLookupLimit = 50;

/// The state of an account whose deletion was requested.
///
/// The account is **not** erased on the spot: it is marked as pending
/// deletion and the purge happens at [scheduledFor], thirty days after the
/// request (D-19).
final class AccountDeletion {
  /// Creates a state.
  const AccountDeletion({
    required this.requestedAt,
    required this.scheduledFor,
    this.retentionDays = accountDeletionRetentionDays,
  });

  /// The moment the author asked for the deletion.
  final DateTime requestedAt;

  /// The moment the data is purged for good.
  final DateTime scheduledFor;

  /// The number of days between the request and the purge.
  final int retentionDays;

  /// Reads a deletion request from an entry of the audit journal.
  ///
  /// The entry is the mark left by the request of an author: it carries the
  /// moment of the request and the deadline of the purge. The deadline is
  /// the source of truth of the purge (D-19): the worker reads it to know
  /// when the data of the account must be erased for good.
  ///
  /// A mark that carries no deadline falls back on the moment of the entry
  /// and on the retention window: the account is purged later, never
  /// earlier.
  factory AccountDeletion.fromEntry(
    AuditEntry entry, {
    int retentionDays = accountDeletionRetentionDays,
  }) {
    final DateTime start =
        _readDate(entry.metadata['requested_at']) ??
        entry.createdAt?.toUtc() ??
        DateTime.now().toUtc();
    final DateTime end =
        _readDate(entry.metadata['scheduled_for']) ??
        start.add(Duration(days: retentionDays));
    return AccountDeletion(
      requestedAt: start,
      scheduledFor: end,
      retentionDays: retentionDays,
    );
  }

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': 'pending_deletion',
      'requested_at': requestedAt.toUtc().toIso8601String(),
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'retention_days': retentionDays,
    };
  }

  /// Reads a date written in the metadata of an entry.
  static DateTime? _readDate(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    if (value is DateTime) return value.toUtc();
    return null;
  }
}

/// The service handling the deletion requests of the accounts.
///
/// The accounts live in the identity provider, not in the database of the
/// API: the request is therefore **marked** in the audit journal, which is
/// the register of the sensitive actions (D-19). The mark is the source of
/// truth of the pending deletions: the purge reads it to know which
/// accounts must be emptied, and when.
final class AccountDeletionService {
  /// Creates the service.
  const AccountDeletionService({
    required this.audit,
    this.retentionDays = accountDeletionRetentionDays,
  });

  /// The audit journal.
  final AuditLog audit;

  /// The number of days between the request and the purge.
  final int retentionDays;

  /// Registers the deletion request of [userId].
  ///
  /// The call is idempotent: a second request answers the very same
  /// deadline and journals nothing. The author never gets a shorter — nor a
  /// longer — retention window because they tapped twice.
  Future<AccountDeletion> request({
    required String userId,
    required String email,
    String? ip,
    DateTime? requestedAt,
  }) async {
    final AccountDeletion? pending = await pendingDeletion(userId: userId);
    if (pending != null) {
      return pending;
    }

    final DateTime moment = requestedAt ?? DateTime.now().toUtc();
    final AccountDeletion deletion = AccountDeletion(
      requestedAt: moment,
      scheduledFor: moment.add(Duration(days: retentionDays)),
      retentionDays: retentionDays,
    );

    await audit.record(
      AuditEntry(
        userId: userId,
        action: accountDeletionRequestedAction,
        targetType: 'account',
        targetId: userId,
        metadata: <String, Object?>{
          'email': email,
          'requested_at': deletion.requestedAt.toUtc().toIso8601String(),
          'scheduled_for': deletion.scheduledFor.toUtc().toIso8601String(),
          'retention_days': retentionDays,
        },
        ip: ip,
        createdAt: moment,
      ),
    );

    return deletion;
  }

  /// The pending deletion of [userId], `null` when there is none.
  ///
  /// Only the entries of the author are read, and only the deletion
  /// requests: the journal never discloses the state of another account,
  /// and the entries that came after the request never hide it.
  Future<AccountDeletion?> pendingDeletion({required String userId}) async {
    final List<AuditEntry> entries = await audit.entriesOf(
      userId: userId,
      limit: accountDeletionLookupLimit,
      action: accountDeletionRequestedAction,
    );
    if (entries.isEmpty) return null;
    return _read(entries.first);
  }

  AccountDeletion _read(AuditEntry entry) {
    return AccountDeletion.fromEntry(entry, retentionDays: retentionDays);
  }
}
