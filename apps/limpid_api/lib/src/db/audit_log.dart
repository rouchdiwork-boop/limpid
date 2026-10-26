import 'audit_entry.dart';

/// The persistence port of the audit journal.
///
/// The journal is append only. It is read back for two reasons only: the
/// export of the personal data of an author carries the entries concerning
/// them, and the state of a pending account deletion is read from the
/// deletion requests it holds (D-19).
abstract interface class AuditLog {
  /// Appends [entry] to the audit journal.
  Future<void> record(AuditEntry entry);

  /// Reads the entries concerning [userId], the most recent first.
  ///
  /// The journal never leaks: the entries of another author are never
  /// returned, whatever the caller asks for. When [action] is given, only
  /// the entries of that action are read — the lookup of a pending account
  /// deletion must not be hidden by the entries that came after it.
  Future<List<AuditEntry>> entriesOf({
    required String userId,
    required int limit,
    String? action,
  });
}
