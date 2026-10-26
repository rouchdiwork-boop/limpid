import 'dart:typed_data';

/// The number of days the data of an account lives after a deletion request.
///
/// The window is the one of D-19: the rows survive thirty days, then the
/// purge removes them for good. The server owns the rule — it answers the
/// exact deadline — this constant only lets the interface announce the delay
/// before the request is sent.
const int accountDeletionRetentionDays = 30;

/// The export of the personal data of the author.
///
/// The file carries everything the server knows about the author: the
/// projects, the manuscripts, the operations of the synchronisation journal
/// and the audit entries concerning them.
final class PersonalDataExport {
  /// Creates an export.
  const PersonalDataExport({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.generatedAt,
    required this.projectCount,
  });

  /// The recommended name of the file.
  final String fileName;

  /// The media type of the file.
  final String mimeType;

  /// The content of the file.
  final Uint8List bytes;

  /// The moment the server produced the export.
  final DateTime generatedAt;

  /// The number of projects the export carries.
  final int projectCount;
}

/// The state of an account whose deletion was requested.
///
/// The account is not erased on the spot: the data lives until
/// [scheduledFor], the day the purge removes it for good.
final class AccountDeletion {
  /// Creates a state.
  const AccountDeletion({
    required this.requestedAt,
    required this.scheduledFor,
    required this.retentionDays,
  });

  /// The moment the author asked for the deletion.
  final DateTime requestedAt;

  /// The moment the data is purged for good.
  final DateTime scheduledFor;

  /// The number of days between the request and the purge.
  final int retentionDays;
}

/// The personal data of the author (RGPD).
///
/// The contract lives in the domain layer (D-31): the settings screen names
/// it, and the implementation of the data layer realises it — neither of them
/// knows the other.
abstract interface class GdprRepository {
  /// Exports the personal data of the author and returns the file.
  ///
  /// Throws a typed error when the server refuses the export or cannot be
  /// reached — the interface never presents a file that was not produced.
  Future<PersonalDataExport> exportPersonalData();

  /// Asks for the deletion of the account and returns its new state.
  ///
  /// The call is idempotent: a second request answers the very same
  /// deadline.
  Future<AccountDeletion> requestAccountDeletion();
}
