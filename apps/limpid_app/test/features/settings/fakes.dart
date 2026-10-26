import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_app/src/domain/gdpr_repository.dart';

/// A [GdprRepository] the test drives by hand.
///
/// The fake records what the interface asks for and answers what the test
/// prepared: a file for the export, a deadline for the deletion.
final class FakeGdprRepository implements GdprRepository {
  /// The number of exports the interface asked for.
  int exportCalls = 0;

  /// The number of deletion requests the interface sent.
  int deletionCalls = 0;

  /// The file the fake produces.
  PersonalDataExport export = PersonalDataExport(
    fileName: 'limpid-donnees.json',
    mimeType: 'application/json',
    bytes: Uint8List.fromList(utf8.encode('{"projects": [], "audit_log": []}')),
    generatedAt: DateTime.utc(2026, 10, 25),
    projectCount: 1,
  );

  /// The state the fake answers for the deletion.
  AccountDeletion deletion = AccountDeletion(
    requestedAt: DateTime.utc(2026, 10, 25),
    scheduledFor: DateTime.utc(2026, 11, 24),
    retentionDays: 30,
  );

  /// The error the fake throws, `null` when it succeeds.
  Object? error;

  /// Called when the interface asks for the deletion of the account.
  ///
  /// The callback lets a test watch the order of the operations: the server
  /// accepts the request, then the local data is erased.
  void Function()? onDeletion;

  @override
  Future<PersonalDataExport> exportPersonalData() async {
    exportCalls++;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return export;
  }

  @override
  Future<AccountDeletion> requestAccountDeletion() async {
    deletionCalls++;
    onDeletion?.call();
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return deletion;
  }
}
