/// Les actions de la page de vente.
///
/// Elles vivent à part de la page : la page dessine, les actions décident.
/// Une action qui échoue le dit à l'acheteur — elle ne fait jamais
/// semblant qu'un paiement a commencé.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'action « Acheter ».
///
/// Elle commande le livre au serveur, puis ouvre l'adresse de paiement que
/// le serveur a renvoyée. Elle ne fait jamais semblant : une commande
/// refusée est dite comme telle, et une adresse absente n'est jamais
/// présentée comme un paiement commencé.
///
/// Le retour du paiement ne se décide pas ici : c'est la liste des achats
/// qui fait foi, et l'écran de retour s'y fie.
Future<void> buyBook(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  final BookOrder order;
  try {
    order = await ref
        .read(bookSaleRepositoryProvider)
        .order(
          projectId: projectId,
          successPath: PublicationRoutes.paymentReturn(projectId),
          cancelPath: PublicationRoutes.sale(projectId),
        );
  } on ServiceUnavailableException {
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.salePaymentUnavailable,
      variant: LimpidStatusVariant.warning,
    );
    return;
  } on ApiNotFoundException {
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.saleNotForSale,
      variant: LimpidStatusVariant.warning,
    );
    return;
  } on Exception {
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.saleOrderFailed,
      variant: LimpidStatusVariant.danger,
    );
    return;
  } on Object catch (error, stackTrace) {
    // Une `Error` — et non une `Exception` — ne remonte pas dans le
    // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
    // bouton semble ne rien faire. L'acheteur voit un message, et la
    // console porte la cause.
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.saleOrderFailed,
      variant: LimpidStatusVariant.danger,
    );
    debugPrint('La commande du livre a échoué : $error\n$stackTrace');
    return;
  }

  if (!context.mounted) return;

  if (order.isFree) {
    // Un livre gratuit n'ouvre aucun paiement : le droit de lecture est
    // accordé tout de suite, et le livre est dans les achats.
    ref.invalidate(bookPurchasesProvider);
    LimpidSnackbar.show(
      context,
      message: strings.saleFreeGranted,
      variant: LimpidStatusVariant.success,
    );
    return;
  }

  final Uri? address = order.hasPaymentUrl
      ? Uri.tryParse(order.paymentUrl!)
      : null;
  if (address == null) {
    // Le serveur n'a renvoyé aucune adresse : la commande n'a pas abouti.
    LimpidSnackbar.show(
      context,
      message: strings.saleOrderFailed,
      variant: LimpidStatusVariant.danger,
    );
    return;
  }

  final bool isOpened = await ref.read(paymentOpenerProvider).open(address);
  if (!context.mounted) return;
  if (isOpened) return;

  // La plateforme ne sait pas ouvrir une page de paiement : l'acheteur le
  // dit, plutôt que de croire qu'il a payé.
  LimpidSnackbar.show(
    context,
    message: strings.salePaymentUnavailable,
    variant: LimpidStatusVariant.warning,
  );
}
