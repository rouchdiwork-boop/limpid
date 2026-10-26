/// L'état des équipes, lu sur le serveur.
///
/// Les écrans des équipes lisent ces états : la liste des équipes, les
/// membres d'une équipe et le nombre de sièges que la formule du compte
/// accorde. Aucun écran n'atteint le serveur lui-même.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';

/// Les équipes du compte, lues sur le serveur.
final teamsProvider = FutureProvider<List<Team>>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(teamRepositoryProvider).listTeams(),
  );
});

/// L'équipe [teamId], lue dans la liste des équipes du compte.
///
/// L'écran d'une équipe lit son nom dans la liste : le serveur ne publie
/// pas une route d'équipe seule.
final teamProvider = Provider.family<Team?, String>((Ref ref, String teamId) {
  final List<Team>? teams = ref.watch(teamsProvider).value;
  if (teams == null) return null;
  for (final Team team in teams) {
    if (team.id == teamId) return team;
  }
  return null;
});

/// Les membres de l'équipe [teamId], lus sur le serveur.
final teamMembersProvider = FutureProvider.family<List<TeamMember>, String>((
  Ref ref,
  String teamId,
) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(teamRepositoryProvider).listMembers(teamId: teamId),
  );
});

/// Les invitations de l'équipe [teamId], lues sur le serveur.
///
/// L'écran ne montre que les invitations du propriétaire : une invitation
/// porte une adresse, et une adresse n'appartient pas à toute l'équipe.
final teamInvitationsProvider =
    FutureProvider.family<List<TeamEmailInvitation>, String>((
      Ref ref,
      String teamId,
    ) async {
      return runWithTwoFactorGlobally(
        ref,
        action: () =>
            ref.watch(teamRepositoryProvider).listInvitations(teamId: teamId),
      );
    });

/// Le nombre de sièges que la formule du compte accorde par équipe.
///
/// La formule est un autre port : son échec ne doit pas cacher les équipes.
/// L'écran montre alors les sièges occupés, sans limite — jamais un chiffre
/// qu'il n'a pas lu.
final teamSeatLimitProvider = FutureProvider<int?>((Ref ref) async {
  try {
    final AccountPlan plan = await ref
        .watch(planRepositoryProvider)
        .currentPlan();
    return plan.seatCount;
  } on Object catch (error) {
    debugPrint(
      'La formule du compte ne dit pas les sièges de l\'équipe ($error).',
    );
    return null;
  }
});

/// Le nombre de sièges occupés par les membres de l'équipe.
///
/// Le propriétaire ne prend pas de siège : les sièges sont les membres
/// invités.
int usedSeatsOf(List<TeamMember> members) {
  int used = 0;
  for (final TeamMember member in members) {
    if (member.takesSeat) used++;
  }
  return used;
}
