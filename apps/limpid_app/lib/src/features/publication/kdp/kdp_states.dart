import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le libellé d'un état de dépôt, dans la langue de l'interface.
String kdpStateLabel(AppLocalizations strings, KdpState state) {
  return switch (state) {
    KdpState.draft => strings.kdpStateDraft,
    KdpState.submitted => strings.kdpStateSubmitted,
    KdpState.live => strings.kdpStateLive,
    KdpState.refused => strings.kdpStateRefused,
    KdpState.failed => strings.kdpStateFailed,
  };
}

/// La variante du badge qui porte un état de dépôt.
///
/// L'état n'est jamais porté par la couleur seule : le badge porte aussi son
/// libellé.
LimpidStatusVariant kdpStateVariant(KdpState state) {
  return switch (state) {
    KdpState.draft => LimpidStatusVariant.neutral,
    KdpState.submitted => LimpidStatusVariant.info,
    KdpState.live => LimpidStatusVariant.success,
    KdpState.refused => LimpidStatusVariant.danger,
    KdpState.failed => LimpidStatusVariant.warning,
  };
}

/// L'état vide de l'écran des dépôts.
///
/// L'auteur n'a encore rien déposé : l'écran lui propose d'en préparer un.
class KdpEmptyState extends StatelessWidget {
  /// Crée l'état.
  const KdpEmptyState({required this.onCreate, super.key});

  /// Appelée quand l'auteur veut préparer un dépôt.
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.kdpEmpty,
        icon: LimpidIcons.upload,
        action: LimpidButton(
          label: strings.kdpCreate,
          icon: LimpidIcons.add,
          onPressed: onCreate,
        ),
      ),
    );
  }
}

/// L'état d'échec de la lecture des dépôts.
class KdpFailureState extends StatelessWidget {
  /// Crée l'état.
  const KdpFailureState({
    required this.error,
    required this.onRetry,
    super.key,
  });

  /// L'erreur qui a fait échouer la lecture.
  final Object error;

  /// Appelée quand l'auteur redemande les dépôts.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    // Deux erreurs disent la même chose à l'auteur : le dépôt n'est pas
    // configuré sur ce poste. Les autres sont des pannes de lecture.
    final Object failure = error;
    final bool isNotConfigured =
        failure is KdpUnavailableException ||
        failure is ServiceUnavailableException;
    final String? reason = failure is KdpUnavailableException
        ? failure.reason
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: isNotConfigured
            ? strings.kdpNotConfigured
            : strings.errorGeneric,
        message: reason,
        icon: isNotConfigured ? LimpidIcons.offline : LimpidIcons.error,
        // Réessayer ne sert à rien quand le service n'existe pas sur ce
        // poste : l'écran ne propose pas un clic qui ne peut pas aboutir.
        action: isNotConfigured
            ? null
            : LimpidButton(
                label: strings.actionRetry,
                icon: LimpidIcons.sync,
                onPressed: onRetry,
              ),
      ),
    );
  }
}

/// La bannière qui dit que le dépôt est impossible sur ce poste.
///
/// Le livre n'est pas parti : l'écran le dit, il ne prétend jamais que le
/// dossier est arrivé chez Amazon.
class KdpNotConfiguredBanner extends StatelessWidget {
  /// Crée la bannière.
  const KdpNotConfiguredBanner({this.reason, super.key});

  /// La raison donnée par le serveur, quand il en donne une.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return LimpidBanner(
      variant: LimpidStatusVariant.warning,
      title: strings.kdpNotConfigured,
      message: reason,
    );
  }
}
