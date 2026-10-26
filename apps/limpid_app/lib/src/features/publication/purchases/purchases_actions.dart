/// Les actions de l'ecran des livres achetes.
///
/// Elles vivent a part de la page : la page dessine, les actions decident.
/// Une action qui echoue le dit a l'acheteur — elle ne fait jamais
/// semblant qu'un fichier a ete telecharge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/purchases/book_file_saver.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'action « Telecharger ».
///
/// Elle demande au serveur une adresse de telechargement, telecharge le
/// fichier a cette adresse, et l'enregistre hors de l'application.
///
/// Elle rend le fichier obtenu : l'ecran s'en sert pour dire quand
/// l'adresse expire, et pour proposer d'en demander une autre.
Future<BookFile?> downloadPurchasedBook(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  final BookFile file;
  try {
    file = await ref.read(bookSaleRepositoryProvider).download(projectId);
  } on ServiceUnavailableException {
    if (!context.mounted) return null;
    LimpidSnackbar.show(
      context,
      message: strings.purchasesDownloadFailed,
      variant: LimpidStatusVariant.warning,
    );
    return null;
  } on ApiNotFoundException {
    // Le compte n'a pas achete ce livre, ou le serveur n'a pas pu produire
    // son fichier : la page le dit, elle n'invente pas un livre.
    if (!context.mounted) return null;
    LimpidSnackbar.show(
      context,
      message: strings.purchasesDownloadFailed,
      variant: LimpidStatusVariant.warning,
    );
    return null;
  } on Exception {
    if (!context.mounted) return null;
    LimpidSnackbar.show(
      context,
      message: strings.purchasesDownloadFailed,
      variant: LimpidStatusVariant.danger,
    );
    return null;
  } on Object catch (error, stackTrace) {
    // Une `Error` — et non une `Exception` — ne remonte pas dans le
    // `on Exception` ci-dessus : sans ce filet, l'echec disparait et le
    // bouton semble ne rien faire. L'acheteur voit un message, et la
    // console porte la cause.
    if (!context.mounted) return null;
    LimpidSnackbar.show(
      context,
      message: strings.purchasesDownloadFailed,
      variant: LimpidStatusVariant.danger,
    );
    debugPrint('Le telechargement du livre a echoue : $error\n$stackTrace');
    return null;
  }

  try {
    await ref.read(bookFileSaverProvider).save(file);
  } on Object catch (error, stackTrace) {
    // Le fichier a bien ete telecharge, mais il n'a pas pu etre enregistre
    // : l'acheteur doit le savoir, plutot que de croire qu'il a le livre.
    if (!context.mounted) return null;
    LimpidSnackbar.show(
      context,
      message: strings.purchasesDownloadFailed,
      variant: LimpidStatusVariant.danger,
    );
    debugPrint(
      'Le fichier du livre n\'a pas ete enregistre : $error\n$stackTrace',
    );
    return null;
  }

  if (!context.mounted) return file;
  LimpidSnackbar.show(
    context,
    message: strings.purchasesDownloaded,
    variant: LimpidStatusVariant.success,
  );
  return file;
}
