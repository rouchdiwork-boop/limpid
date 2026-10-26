import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// The state of the export of the personal data.
@immutable
class PersonalDataExportState {
  /// Creates the state.
  const PersonalDataExportState({this.isRunning = false, this.result});

  /// Whether an export is running.
  final bool isRunning;

  /// The last export produced, `null` when there is none.
  final PersonalDataExport? result;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonalDataExportState &&
          other.isRunning == isRunning &&
          other.result == result);

  @override
  int get hashCode => Object.hash(isRunning, result);
}

/// Runs the export of the personal data on demand.
final personalDataExportProvider =
    NotifierProvider<PersonalDataExportNotifier, PersonalDataExportState>(
      PersonalDataExportNotifier.new,
    );

/// Runs the export and keeps the produced file.
final class PersonalDataExportNotifier
    extends Notifier<PersonalDataExportState> {
  @override
  PersonalDataExportState build() => const PersonalDataExportState();

  /// Exports the personal data of the author.
  ///
  /// The error is not swallowed: the screen catches it and shows what the
  /// server answered.
  Future<PersonalDataExport?> export() async {
    if (state.isRunning) {
      return state.result;
    }
    state = PersonalDataExportState(isRunning: true, result: state.result);
    try {
      final PersonalDataExport result = await ref
          .read(gdprRepositoryProvider)
          .exportPersonalData();
      state = PersonalDataExportState(isRunning: false, result: result);
      return result;
    } on Object {
      state = PersonalDataExportState(isRunning: false, result: state.result);
      rethrow;
    }
  }
}

/// The state of the deletion request of the account.
@immutable
class AccountDeletionState {
  /// Creates the state.
  const AccountDeletionState({this.isRunning = false, this.result});

  /// Whether a request is running.
  final bool isRunning;

  /// The last deletion request registered, `null` when there is none.
  final AccountDeletion? result;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountDeletionState &&
          other.isRunning == isRunning &&
          other.result == result);

  @override
  int get hashCode => Object.hash(isRunning, result);
}

/// Registers the deletion request of the account on demand.
final accountDeletionProvider =
    NotifierProvider<AccountDeletionNotifier, AccountDeletionState>(
      AccountDeletionNotifier.new,
    );

/// Registers the deletion request and keeps the state of the account.
final class AccountDeletionNotifier extends Notifier<AccountDeletionState> {
  @override
  AccountDeletionState build() => const AccountDeletionState();

  /// Asks for the deletion of the account.
  ///
  /// The error is not swallowed: the screen catches it and shows what the
  /// server answered.
  Future<AccountDeletion?> requestDeletion() async {
    if (state.isRunning) {
      return state.result;
    }
    state = AccountDeletionState(isRunning: true, result: state.result);
    try {
      final AccountDeletion result = await ref
          .read(gdprRepositoryProvider)
          .requestAccountDeletion();
      state = AccountDeletionState(isRunning: false, result: result);
      return result;
    } on Object {
      state = AccountDeletionState(isRunning: false, result: state.result);
      rethrow;
    }
  }
}
