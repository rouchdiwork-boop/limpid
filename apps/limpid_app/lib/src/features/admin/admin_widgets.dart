import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'état d'échec d'une lecture du back-office.
///
/// Le refus de l'administrateur n'est pas une panne : l'écran dit que la
/// page est réservée aux administrateurs, et il ne propose pas de réessayer
/// — une nouvelle demande serait refusée de la même manière.
///
/// L'absence de service distant n'est pas un échec non plus : l'écran le dit
/// et montre l'état de démonstration, jamais une liste vide.
class AdminFailureState extends StatelessWidget {
  /// Crée l'état d'échec.
  const AdminFailureState({super.key, required this.error, this.onRetry});

  /// L'erreur qui a fait échouer la lecture.
  final Object error;

  /// Appelé quand l'administrateur demande une nouvelle lecture.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);

    if (error is ApiUnauthorizedException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.warning,
        title: strings.adminForbiddenTitle,
        message: strings.adminForbiddenMessage,
      );
    }
    if (error is ServiceUnavailableException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.demoModeTitle,
        message: strings.demoModeMessage,
      );
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      icon: LimpidIcons.error,
      action: onRetry == null
          ? null
          : LimpidButton(label: strings.actionRetry, onPressed: onRetry),
    );
  }
}

/// La carte d'un compte dans la liste du back-office.
///
/// La carte montre ce que le serveur sait du compte : son identifiant, son
/// adresse quand il la publie, sa formule et son usage. Elle ne montre
/// jamais une adresse que le serveur n'a pas donnée.
class AdminAccountCard extends StatelessWidget {
  /// Crée la carte d'un compte.
  const AdminAccountCard({super.key, required this.account, this.onTap});

  /// Le compte montré par la carte.
  final AdminAccount account;

  /// Appelé quand la carte est touchée.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? plan = account.plan;
    final String? email = account.email;

    return LimpidCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(LimpidIcons.user, size: 18),
              SizedBox(width: scope.spacing.space8),
              Expanded(
                child: Text(
                  account.userId,
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (plan != null)
                LimpidBadge(label: plan, variant: LimpidStatusVariant.success),
            ],
          ),
          if (email != null) ...<Widget>[
            SizedBox(height: scope.spacing.space4),
            Text(
              email,
              style: textTheme.bodyMedium?.copyWith(
                color: scope.colors.fgMuted,
              ),
            ),
          ],
          SizedBox(height: scope.spacing.space12),
          Wrap(
            spacing: scope.spacing.space8,
            runSpacing: scope.spacing.space4,
            children: <Widget>[
              LimpidBadge(
                label: strings.adminAccountProjects(account.projectCount),
              ),
              LimpidBadge(
                label: strings.adminAccountCollaborations(
                  account.collaborationCount,
                ),
              ),
              LimpidBadge(
                label: strings.adminAccountMessages(account.commentCount),
              ),
              LimpidBadge(
                label: strings.adminAccountOperations(account.operationCount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La carte d'un indicateur de fonctionnalité.
///
/// L'interrupteur de la carte active ou désactive l'indicateur. Il est en
/// lecture seule pendant que la demande voyage : l'administrateur voit
/// alors l'état que le serveur a rendu, jamais un état qu'il a deviné.
class AdminFeatureFlagCard extends StatelessWidget {
  /// Crée la carte d'un indicateur.
  const AdminFeatureFlagCard({super.key, required this.flag, this.onChanged});

  /// L'indicateur montré par la carte.
  final AdminFeatureFlag flag;

  /// Appelé quand l'administrateur change l'état de l'indicateur.
  ///
  /// Un callback nul rend l'interrupteur en lecture seule.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String description = flag.description;

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // L'interrupteur est une tuile : il peint ses effets sur le
          // `Material` le plus proche. La carte est une `DecoratedBox` —
          // l'interrupteur a besoin de son propre `Material`, sans quoi ses
          // effets seraient invisibles.
          Material(
            type: MaterialType.transparency,
            child: LimpidSwitch(
              value: flag.isEnabled,
              onChanged: onChanged,
              label: flag.key,
              description: description.isEmpty ? null : description,
            ),
          ),
          SizedBox(height: scope.spacing.space8),
          Text(
            strings.adminFlagUpdatedBy(flag.updatedBy),
            style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
        ],
      ),
    );
  }
}
