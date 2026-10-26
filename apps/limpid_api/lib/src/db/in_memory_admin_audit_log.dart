import 'audit_entry.dart';
import 'audit_log.dart';

/// An in-memory [AuditLog], used by the test suite and by the back-office
/// that runs without a database.
///
/// The journal is append only, like the SQL ones: an entry is written and
/// never modified. The entries are read back by the account they concern.
final class InMemoryAdminAuditLog implements AuditLog {
  /// Creates an empty journal.
  InMemoryAdminAuditLog();

  final List<AuditEntry> _entries = <AuditEntry>[];

  /// The entries of the journal, the most recent first.
  List<AuditEntry> get entries => List<AuditEntry>.unmodifiable(_entries);

  @override
  Future<void> record(AuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<AuditEntry>> entriesOf({
    required String userId,
    required int limit,
    String? action,
  }) async {
    final List<AuditEntry> matching =
        _entries
            .where(
              (AuditEntry entry) =>
                  entry.userId == userId &&
                  (action == null || entry.action == action),
            )
            .toList(growable: false)
          ..sort((AuditEntry left, AuditEntry right) {
            final int byDate = _momentOf(right).compareTo(_momentOf(left));
            if (byDate != 0) return byDate;
            return right.targetId.compareTo(left.targetId);
          });
    return List<AuditEntry>.unmodifiable(matching.take(limit));
  }

  /// The moment of an entry, the epoch when it carries none.
  static DateTime _momentOf(AuditEntry entry) =>
      entry.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
