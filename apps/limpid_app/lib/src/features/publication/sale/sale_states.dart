import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'état de la page de vente pendant la lecture du prix.
class BookSaleLoading extends StatelessWidget {
  /// Crée l'état.
  const BookSaleLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space80),
      child: const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
    );
  }
}

/// L'état de la page de vente quand le prix n'a pas pu être lu.
class BookSaleFailure extends StatelessWidget {
  /// Crée l'état.
  const BookSaleFailure({required this.onRetry, super.key});

  /// Appelé quand le lecteur redemande le livre.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.errorGeneric,
        message: strings.dataEmptyMessage,
        icon: LimpidIcons.error,
        action: LimpidButton(
          label: strings.actionRetry,
          icon: LimpidIcons.sync,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

/// L'état de la page de vente d'un livre qui n'est pas en vente.
///
/// La page ne montre **aucun prix** : un livre qui n'est pas en vente n'a
/// pas de prix, et en afficher un serait en inventer un.
class BookSaleNotForSale extends StatelessWidget {
  /// Crée l'état.
  const BookSaleNotForSale({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.saleNotForSale,
        message: strings.saleNotForSaleMessage,
        icon: LimpidIcons.money,
      ),
    );
  }
}

/// L'état de la page de vente pour un lecteur sans compte.
///
/// Le prix et l'achat sont réservés aux comptes connectés : la page le dit
/// et propose de se connecter, plutôt que d'afficher un prix que le
/// serveur n'a pas donné.
class BookSaleSignInRequired extends StatelessWidget {
  /// Crée l'état.
  const BookSaleSignInRequired({required this.onSignIn, super.key});

  /// Appelé quand le lecteur veut se connecter.
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.saleSignInRequired,
        message: strings.saleSignInRequiredMessage,
        icon: LimpidIcons.user,
        action: LimpidButton(
          label: strings.saleSignInAction,
          icon: LimpidIcons.user,
          onPressed: onSignIn,
        ),
      ),
    );
  }
}
