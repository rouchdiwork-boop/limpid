import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_labels.dart';
import 'package:limpid_app/src/features/teams/teams_actions.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La liste des membres d'une équipe, avec leurs rôles.
///
/// La section montre le rôle de chaque membre et n'offre que les actions que
/// le serveur autorise : le propriétaire invite et retire, un membre quitte
/// l'équipe. Le rôle du propriétaire ne se change pas.
class TeamMembersSection extends StatelessWidget {
  /// Crée la section.
  const TeamMembersSection({
    required this.members,
    required this.currentUserId,
    required this.canManage,
    required this.onInvite,
    required this.onInviteByEmail,
    required this.onRoleChanged,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  /// Les membres de l'équipe, lus sur le serveur.
  final AsyncValue<List<TeamMember>> members;

  /// L'identifiant du compte de l'auteur.
  final String? currentUserId;

  /// L'auteur est-il le propriétaire de l'équipe ?
  final bool canManage;

  /// Appelé quand l'auteur invite un compte existant.
  final VoidCallback onInvite;

  /// Appelé quand l'auteur invite une adresse.
  final VoidCallback onInviteByEmail;

  /// Appelé quand l'auteur change le rôle d'un membre.
  final void Function(TeamMember member, TeamRole role) onRoleChanged;

  /// Appelé quand l'auteur retire un membre — ou quitte l'équipe.
  final void Function(TeamMember member) onRemove;

  /// Appelé quand l'auteur veut relire les membres.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                strings.teamsMembers,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (canManage) ...<Widget>[
              LimpidButton(
                label: strings.teamsInviteEmail,
                variant: LimpidButtonVariant.secondary,
                size: LimpidButtonSize.small,
                onPressed: onInviteByEmail,
              ),
              SizedBox(width: scope.spacing.space8),
              LimpidButton(
                label: strings.teamsInvite,
                icon: LimpidIcons.add,
                size: LimpidButtonSize.small,
                onPressed: onInvite,
              ),
            ],
          ],
        ),
        SizedBox(height: scope.spacing.space12),
        members.when(
          loading: () => const Center(child: LimpidSpinner()),
          error: (Object error, StackTrace stack) => _failure(context, error),
          data: (List<TeamMember> list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final TeamMember member in list) _member(context, member),
            ],
          ),
        ),
      ],
    );
  }

  /// La carte d'un membre.
  Widget _member(BuildContext context, TeamMember member) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final bool isSelf = member.userId == currentUserId;
    final bool isOwner = member.role == TeamRole.owner;

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
                    member.userId,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                SizedBox(width: scope.spacing.space12),
                LimpidBadge(
                  label: teamRoleLabel(strings, member.role),
                  variant: isOwner
                      ? LimpidStatusVariant.info
                      : LimpidStatusVariant.neutral,
                ),
              ],
            ),
            if (canManage && !isOwner) ...<Widget>[
              SizedBox(height: scope.spacing.space12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: LimpidSelect<TeamRole>(
                      label: strings.teamsRole,
                      value: member.role,
                      items: <LimpidSelectItem<TeamRole>>[
                        for (final TeamRole candidate in assignableTeamRoles)
                          LimpidSelectItem<TeamRole>(
                            value: candidate,
                            label: teamRoleLabel(strings, candidate),
                          ),
                      ],
                      onChanged: (TeamRole? role) {
                        if (role == null) return;
                        onRoleChanged(member, role);
                      },
                    ),
                  ),
                  SizedBox(width: scope.spacing.space12),
                  LimpidButton(
                    label: strings.teamsRemove,
                    variant: LimpidButtonVariant.danger,
                    size: LimpidButtonSize.small,
                    onPressed: () => onRemove(member),
                  ),
                ],
              ),
            ] else if (isSelf && !isOwner) ...<Widget>[
              SizedBox(height: scope.spacing.space12),
              Align(
                alignment: Alignment.centerLeft,
                child: LimpidButton(
                  label: strings.teamsLeave,
                  variant: LimpidButtonVariant.secondary,
                  size: LimpidButtonSize.small,
                  onPressed: () => onRemove(member),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// L'état d'échec de la lecture des membres.
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
