import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'etat de l'ecran des livres achetes pendant la lecture des achats.
class PurchasesLoading extends StatelessWidget {
  /// Cree l'etat.
  const PurchasesLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space80),
      child: const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
    );
  }
}

/// L'etat de l'ecran des livres achetes quand la liste n'a pas pu etre lue.
class PurchasesFailure extends StatelessWidget {
  /// Cree l'etat.
  const PurchasesFailure({required this.onRetry, super.key});

  /// Appele quand l'acheteur redemande ses livres.
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

/// L'etat de l'ecran des livres achetes d'un compte qui n'a rien achete.
class PurchasesEmpty extends StatelessWidget {
  /// Cree l'etat.
  const PurchasesEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space32),
      child: LimpidEmptyState(
        title: strings.purchasesEmpty,
        message: strings.purchasesEmptyMessage,
        icon: LimpidIcons.empty,
      ),
    );
  }
}
