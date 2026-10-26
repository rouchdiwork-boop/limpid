import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_labels.dart';
import 'package:limpid_app/src/features/teams/teams_actions.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Les invitations par adresse de l'équipe, avec leur état.
///
/// La section montre ce que l'invitation attend : l'adresse invitée, le
/// rôle, l'échéance. Le propriétaire révoque celles qui ne doivent plus
/// être acceptées.
///
/// L'invitation acceptée reste dans la liste, avec son état : elle est
/// devenue un membre, et l'équipe la montre aussi dans sa liste de membres.
class TeamInvitationsSection extends StatelessWidget {
  /// Crée la section.
  const TeamInvitationsSection({
    required this.invitations,
    required this.canManage,
    required this.onRevoke,
    required this.onRetry,
    super.key,
  });

  /// Les invitations de l'équipe, lues sur le serveur.
  final AsyncValue<List<TeamEmailInvitation>> invitations;

  /// L'auteur est-il le propriétaire de l'équipe ?
  final bool canManage;

  /// Appelé quand l'auteur révoque une invitation.
  final void Function(TeamEmailInvitation invitation) onRevoke;

  /// Appelé quand l'auteur veut relire les invitations.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return invitations.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) => _failure(context, error),
      data: (List<TeamEmailInvitation> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final TeamEmailInvitation invitation in list)
            _row(context, invitation),
        ],
      ),
    );
  }

  /// La carte d'une invitation.
  Widget _row(BuildContext context, TeamEmailInvitation invitation) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final String date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(invitation.expiresAt.toLocal());
    final bool isPending = invitation.isPending;

    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space12),
      child: LimpidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    invitation.email,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                SizedBox(width: scope.spacing.space12),
                LimpidBadge(
                  label: teamInvitationStatusLabel(
                    strings,
                    invitation.status,
                    expiresAt: strings.shareExpiresAt(date),
                  ),
                  variant: teamInvitationStatusVariant(invitation.status),
                ),
              ],
            ),
            SizedBox(height: scope.spacing.space8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    teamRoleLabel(strings, invitation.role),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgMuted,
                    ),
                  ),
                ),
                // L'échéance ne dit quelque chose que tant que l'invitation
                // attend : une invitation expirée porte sa date dans son
                // état, une invitation révoquée n'en a plus.
                if (isPending)
                  Text(
                    strings.shareExpiresAt(date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgMuted,
                    ),
                  ),
              ],
            ),
            if (canManage && isPending) ...<Widget>[
              SizedBox(height: scope.spacing.space12),
              Align(
                alignment: Alignment.centerLeft,
                child: LimpidButton(
                  label: strings.shareRevoke,
                  variant: LimpidButtonVariant.ghost,
                  size: LimpidButtonSize.small,
                  onPressed: () => onRevoke(invitation),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// L'état d'échec de la lecture des invitations.
  ///
  /// Une équipe qui n'existe pas — ou qui appartient à un autre compte —
  /// répond 404 : l'écran le dit, il ne montre jamais une liste vide qui
  /// laisserait croire que tout va bien.
  Widget _failure(BuildContext context, Object error) {
    final AppLocalizations strings = AppLocalizations.of(context);

    if (isTeamServiceMissing(error)) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.demoModeTitle,
        message: strings.demoModeMessage,
      );
    }

    return LimpidBanner(
      variant: LimpidStatusVariant.danger,
      title: teamFailureMessage(strings, error),
      action: LimpidButton(
        label: strings.actionRetry,
        variant: LimpidButtonVariant.text,
        size: LimpidButtonSize.small,
        onPressed: onRetry,
      ),
    );
  }
}
