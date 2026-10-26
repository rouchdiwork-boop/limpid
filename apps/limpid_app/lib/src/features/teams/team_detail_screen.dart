import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_invitations_section.dart';
import 'package:limpid_app/src/features/teams/team_members_section.dart';
import 'package:limpid_app/src/features/teams/teams_actions.dart';
import 'package:limpid_app/src/features/teams/teams_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La page d'une équipe : ses membres, leurs rôles et ses sièges.
///
/// La page montre ce que le serveur a répondu : les membres et leur rôle, le
/// nombre de sièges occupés, et les actions que le compte peut faire. Une
/// équipe qui n'existe pas — ou qui appartient à un autre compte — est une
/// erreur, jamais une liste vide.
class TeamDetailScreen extends ConsumerWidget {
  /// Crée la page.
  const TeamDetailScreen({required this.teamId, super.key});

  /// L'identifiant de l'équipe.
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<TeamMember>> members = ref.watch(
      teamMembersProvider(teamId),
    );
    final AsyncValue<List<TeamEmailInvitation>> invitations = ref.watch(
      teamInvitationsProvider(teamId),
    );
    final int? seatLimit = ref.watch(teamSeatLimitProvider).value;
    final Team? team = ref.watch(teamProvider(teamId));
    final String? userId = ref.watch(sessionControllerProvider).value?.userId;
    // La liste des membres fait foi : elle dit le rôle du compte dans
    // l'équipe, là où la liste des équipes ne dit que le propriétaire.
    final bool canManage =
        userId != null &&
        (members.value?.any(
              (TeamMember member) =>
                  member.userId == userId && member.role == TeamRole.owner,
            ) ??
            false);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings, team),
            SizedBox(height: scope.spacing.space16),
            _seats(context, strings, members.value, seatLimit),
            SizedBox(height: scope.spacing.space32),
            TeamMembersSection(
              members: members,
              currentUserId: userId,
              canManage: canManage,
              onInvite: () => inviteMember(context, ref, teamId: teamId),
              onInviteByEmail: () =>
                  inviteByEmail(context, ref, teamId: teamId),
              onRoleChanged: (TeamMember member, TeamRole role) =>
                  changeMemberRole(
                    context,
                    ref,
                    teamId: teamId,
                    member: member,
                    role: role,
                  ),
              onRemove: (TeamMember member) =>
                  removeMember(context, ref, teamId: teamId, member: member),
              onRetry: () => ref.invalidate(teamMembersProvider(teamId)),
            ),
            if (canManage) ...<Widget>[
              SizedBox(height: scope.spacing.space32),
              TeamInvitationsSection(
                invitations: invitations,
                canManage: canManage,
                onRevoke: (TeamEmailInvitation invitation) => revokeInvitation(
                  context,
                  ref,
                  teamId: teamId,
                  invitation: invitation,
                ),
                onRetry: () => ref.invalidate(teamInvitationsProvider(teamId)),
              ),
            ],
            SizedBox(height: scope.spacing.space32),
            if (canManage)
              LimpidButton(
                label: strings.apiKeysDelete,
                variant: LimpidButtonVariant.danger,
                expand: true,
                onPressed: () => deleteTeam(context, ref, teamId: teamId),
              ),
          ],
        ),
      ),
    );
  }

  /// Le nom de l'équipe.
  Widget _header(BuildContext context, AppLocalizations strings, Team? team) {
    final LimpidThemeScope scope = context.limpid;

    return Text(
      team?.name ?? strings.teamsTitle,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        color: scope.colors.fgDefault,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Le nombre de sièges occupés et la limite de la formule.
  Widget _seats(
    BuildContext context,
    AppLocalizations strings,
    List<TeamMember>? members,
    int? limit,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final int used = usedSeatsOf(members ?? const <TeamMember>[]);
    final bool isFull = limit != null && used >= limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.teamsSeats,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: scope.spacing.space4),
        Text(
          // Les arguments de la chaîne sont ordonnés par nom : le total
          // passe avant l'usage, comme dans le reste de l'application.
          limit == null ? '$used' : strings.teamsSeatsUsed('$limit', '$used'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
        ),
        if (isFull) ...<Widget>[
          SizedBox(height: scope.spacing.space12),
          LimpidBanner(
            variant: LimpidStatusVariant.warning,
            title: strings.teamsSeatFull,
          ),
        ],
      ],
    );
  }
}
