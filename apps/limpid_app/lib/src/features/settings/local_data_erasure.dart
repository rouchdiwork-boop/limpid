import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The outcome of the erasure of the local data of the account.
enum LocalDataErasure {
  /// The local data of the account was erased from the device.
  erased,

  /// This machine holds no local database to erase.
  unavailable,

  /// The erasure failed.
  failed,
}

/// The choice of the author about the local data of the account.
enum LocalDataChoice {
  /// The local data of the account is erased from the device.
  erase,

  /// The local data of the account stays on the device.
  keep,

  /// The author closes the dialog without choosing.
  cancel,
}

/// Asks the author what to do with the local data of the account.
///
/// The dialog says what the erasure removes: the manuscripts of the device
/// are erased, the account itself stays on the server.
Future<LocalDataChoice> showLocalDataErasureChoice(BuildContext context) {
  final AppLocalizations strings = AppLocalizations.of(context);

  return showDialog<LocalDataChoice>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.settingsEraseLocalDataTitle,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () =>
                Navigator.of(dialogContext).pop(LocalDataChoice.cancel),
          ),
          LimpidButton(
            label: strings.settingsEraseLocalDataKeep,
            variant: LimpidButtonVariant.secondary,
            onPressed: () =>
                Navigator.of(dialogContext).pop(LocalDataChoice.keep),
          ),
          LimpidButton(
            label: strings.settingsEraseLocalDataConfirm,
            variant: LimpidButtonVariant.danger,
            onPressed: () =>
                Navigator.of(dialogContext).pop(LocalDataChoice.erase),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LimpidListTile(
              title: strings.settingsEraseLocalDataMessage,
              leading: const Icon(LimpidIcons.delete),
            ),
          ],
        ),
      );
    },
  ).then((LocalDataChoice? choice) => choice ?? LocalDataChoice.cancel);
}

/// Erases the local data of the account from the device.
///
/// The erasure is the right to erasure on the device (D-19): once it ran,
/// the machine holds no manuscript, no scene, no snapshot and no pending
/// operation of the author. The library is refreshed right away — the
/// interface must never show a manuscript that no longer exists.
///
/// The failure is never swallowed: the outcome tells the caller what
/// happened, and the caller shows it to the author.
Future<LocalDataErasure> eraseLocalData(WidgetRef ref) async {
  try {
    await ref.read(localDataEraserProvider)();
    refreshLibraryProviders(ref);
    return LocalDataErasure.erased;
  } on ServiceUnavailableException {
    return LocalDataErasure.unavailable;
  } on Exception {
    return LocalDataErasure.failed;
  }
}

/// Shows the author that the local data could not be erased.
///
/// The session is closed anyway: the author asked to leave, and a failure of
/// the erasure must not keep a session open.
void showLocalDataErasureFailure(
  BuildContext context,
  LocalDataErasure outcome,
) {
  if (outcome == LocalDataErasure.erased) {
    return;
  }
  final AppLocalizations strings = AppLocalizations.of(context);
  final (String message, LimpidStatusVariant variant) = switch (outcome) {
    LocalDataErasure.unavailable => (
      strings.settingsLocalDataEraseUnavailable,
      LimpidStatusVariant.warning,
    ),
    LocalDataErasure.failed => (
      strings.settingsLocalDataEraseFailed,
      LimpidStatusVariant.danger,
    ),
    LocalDataErasure.erased => (strings.errorGeneric, LimpidStatusVariant.info),
  };
  LimpidSnackbar.show(context, message: message, variant: variant);
}

/// Closes the session of the author and sends them back to the sign in.
///
/// The session of an account the author asked to erase is closed too: the
/// application must not keep a session for an account that is disappearing.
Future<void> closeSession(BuildContext context, WidgetRef ref) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  try {
    await ref.read(authRepositoryProvider).signOut();
    if (!context.mounted) {
      return;
    }
    context.go(AppRoutes.signIn);
  } on AuthException catch (error) {
    if (!context.mounted) {
      return;
    }
    LimpidSnackbar.show(
      context,
      message: error.message,
      variant: LimpidStatusVariant.danger,
    );
  } on Exception {
    if (!context.mounted) {
      return;
    }
    LimpidSnackbar.show(
      context,
      message: strings.errorGeneric,
      variant: LimpidStatusVariant.danger,
    );
  }
}
