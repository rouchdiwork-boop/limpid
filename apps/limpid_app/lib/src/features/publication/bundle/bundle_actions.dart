/// Les actions de la page du bundle.
///
/// Elles vivent à part de la page : la page dessine, les actions décident.
/// Une action qui échoue le dit à l'acheteur — elle ne fait jamais
/// semblant qu'un paiement a commencé.
///
/// Le retour du paiement ne se décide pas ici : c'est la liste des achats
/// qui fait foi, et l'écran de retour s'y fie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_routes.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'action « Acheter » d'un bundle.
///
/// Elle commande le bundle au serveur, puis ouvre l'adresse de paiement que
/// le serveur a renvoyée. Elle ne fait jamais semblant : une commande
/// refusée est dite comme telle, et une adresse absente n'est jamais
/// présentée comme un paiement commencé.
Future<void> buyBundle(
  BuildContext context,
  WidgetRef ref,
  String bundleId,
) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  final BundleOrder order;
  try {
    order = await ref
        .read(bundleRepositoryProvider)
        .order(
          bundleId: bundleId,
          successPath: BundleRoutes.paymentReturn(bundleId),
          cancelPath: BundleRoutes.bundle(bundleId),
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
      message: strings.bundleNotForSale,
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
    debugPrint('La commande du bundle a échoué : $error\n$stackTrace');
    return;
  }

  if (!context.mounted) return;

  if (order.isFree) {
    // Un bundle gratuit n'ouvre aucun paiement : les droits de lecture sont
    // accordés tout de suite, et les livres sont dans les achats.
    ref.invalidate(bookPurchasesProvider);
    LimpidSnackbar.show(
      context,
      message: strings.bundleFreeGranted,
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
