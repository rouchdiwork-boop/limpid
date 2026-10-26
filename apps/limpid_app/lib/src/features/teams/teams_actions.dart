/// Les actions de l'écran des équipes.
///
/// Elles vivent à part de la page : la page dessine, les actions décident.
/// Une action qui échoue le dit à l'auteur — elle ne fait jamais semblant
/// qu'une équipe a été créée, qu'un membre a été invité ou qu'un rôle a
/// changé.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_app/src/features/teams/teams_dialogs.dart';
import 'package:limpid_app/src/features/teams/teams_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Crée une équipe et la montre dans la liste.
///
/// La création va au serveur : elle passe par la fenêtre du second facteur,
/// et est répétée quand le serveur refuse la preuve. L'équipe refusée n'a
/// jamais été créée : la répétition n'en crée donc qu'une.
Future<void> createTeam(BuildContext context, WidgetRef ref) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final String? name = await showCreateTeamDialog(context);
  if (name == null || !context.mounted) return;

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref.read(teamRepositoryProvider).createTeam(name: name),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamsProvider);
}

/// Invite un compte dans l'équipe [teamId].
///
/// L'invitation d'un compte existant **s'applique tout de suite** : le
/// membre entre dans l'équipe. L'invitation par adresse attend une réponse.
///
/// L'invitation va au serveur : elle passe par la fenêtre du second facteur.
Future<void> inviteMember(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final TeamAccountInviteRequest? request = await showInviteByAccountDialog(
    context,
  );
  if (request == null || !context.mounted) return;

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref
          .read(teamRepositoryProvider)
          .invite(teamId: teamId, userId: request.userId, role: request.role),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error, isInvitation: true);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamMembersProvider(teamId));
  LimpidSnackbar.show(
    context,
    message: strings.teamsInviteSent,
    variant: LimpidStatusVariant.success,
  );
}

/// Invite l'adresse dans l'équipe [teamId].
///
/// L'invitation va au serveur : elle passe par la fenêtre du second facteur.
/// Elle **attend** : le membre n'entre dans l'équipe qu'à l'acceptation.
///
/// Le lien n'est montré **une seule fois**, et seulement quand aucun
/// fournisseur de courriel n'est configuré : quand le courriel part, le lien
/// n'est plus rendu.
Future<void> inviteByEmail(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final TeamEmailInviteRequest? request = await showInviteByEmailDialog(
    context,
  );
  if (request == null || !context.mounted) return;

  final CreatedTeamInvitation? created = await _createInvitation(
    context,
    ref,
    teamId: teamId,
    request: request,
  );
  if (created == null || !context.mounted) return;

  ref.invalidate(teamInvitationsProvider(teamId));
  final String? link = created.link;
  if (link != null && link.isNotEmpty) {
    await showInvitationLinkDialog(context, link: link);
  }
  if (!context.mounted) return;
  LimpidSnackbar.show(
    context,
    message: strings.teamsInviteSent,
    variant: LimpidStatusVariant.success,
  );
}

/// La création de l'invitation, `null` quand le serveur refuse.
///
/// L'échec est dit à l'auteur : l'action ne fait jamais semblant qu'une
/// invitation a été créée.
Future<CreatedTeamInvitation?> _createInvitation(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  required TeamEmailInviteRequest request,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  try {
    return await runWithTwoFactor(
      context,
      ref,
      action: () => ref
          .read(teamRepositoryProvider)
          .inviteByEmail(
            teamId: teamId,
            email: request.email,
            role: request.role,
          ),
    );
  } on Exception catch (error) {
    if (!context.mounted) return null;
    _showFailure(context, strings, error, isInvitation: true);
    return null;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return null;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return null;
  }
}

/// Révoque l'invitation [invitation] de l'équipe [teamId].
///
/// La révocation va au serveur : elle passe par la fenêtre du second
/// facteur. Une invitation révoquée n'est plus acceptée : le jeton ne
/// marche qu'une fois, et celui-là ne marche plus.
Future<void> revokeInvitation(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  required TeamEmailInvitation invitation,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref
          .read(teamRepositoryProvider)
          .revokeInvitation(teamId: teamId, invitationId: invitation.id),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamInvitationsProvider(teamId));
  LimpidSnackbar.show(
    context,
    message: strings.shareRevoked,
    variant: LimpidStatusVariant.success,
  );
}

/// Accepte l'invitation que porte le jeton [token].
///
/// L'acceptation va au serveur : elle passe par la fenêtre du second
/// facteur. Le serveur refuse un jeton inconnu, expiré, révoqué ou déjà
/// accepté : il répond la même chose dans les quatre cas.
Future<TeamEmailInvitation?> acceptInvitation(
  BuildContext context,
  WidgetRef ref, {
  required String token,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    final TeamEmailInvitation accepted = await runWithTwoFactor(
      context,
      ref,
      action: () =>
          ref.read(teamRepositoryProvider).acceptInvitation(token: token),
    );
    if (!context.mounted) return accepted;
    ref.invalidate(teamMembersProvider(accepted.teamId));
    ref.invalidate(teamInvitationsProvider(accepted.teamId));
    return accepted;
  } on Exception catch (error) {
    if (!context.mounted) return null;
    _showFailure(context, strings, error);
    return null;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return null;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return null;
  }
}

/// Change le rôle du membre [member] dans l'équipe [teamId].
///
/// Le changement de rôle va au serveur : il passe par la fenêtre du second
/// facteur.
Future<void> changeMemberRole(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  required TeamMember member,
  required TeamRole role,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref
          .read(teamRepositoryProvider)
          .changeRole(teamId: teamId, userId: member.userId, role: role),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamMembersProvider(teamId));
}

/// Retire le membre [member] de l'équipe [teamId].
///
/// Le propriétaire retire un membre, un membre quitte l'équipe lui-même : le
/// serveur fait les deux.
///
/// Le retrait va au serveur : il passe par la fenêtre du second facteur.
Future<void> removeMember(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  required TeamMember member,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref
          .read(teamRepositoryProvider)
          .removeMember(teamId: teamId, userId: member.userId),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamMembersProvider(teamId));
}

/// Supprime l'équipe [teamId] et quitte sa page.
///
/// La suppression va au serveur : elle passe par la fenêtre du second
/// facteur.
Future<void> deleteTeam(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final bool confirmed = await showDeleteTeamDialog(context);
  if (!confirmed || !context.mounted) return;

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref.read(teamRepositoryProvider).deleteTeam(teamId: teamId),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showUnexpectedFailure(context, strings, error, stackTrace);
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(teamsProvider);
  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
}

/// Le message d'un échec, pour l'auteur.
///
/// Le serveur écrit ses messages en français, à destination de l'auteur :
/// l'écran les montre quand il en a un. Les autres échecs — un service
/// absent, un réseau coupé — gardent le message générique de l'interface.
String teamFailureMessage(AppLocalizations strings, Object error) {
  if (error is ApiException && error.message.isNotEmpty) return error.message;
  return strings.errorGeneric;
}

/// L'échec vient-il d'un service qui n'est pas configuré ?
bool isTeamServiceMissing(Object error) => error is ServiceUnavailableException;

/// Montre l'échec d'une action à l'auteur.
///
/// Une invitation refusée faute de siège est un avertissement, pas une
/// erreur : l'équipe est pleine, elle n'est pas cassée.
void _showFailure(
  BuildContext context,
  AppLocalizations strings,
  Object error, {
  bool isInvitation = false,
}) {
  if (isInvitation &&
      error is ApiException &&
      error.code == 'plan_limit_reached') {
    LimpidSnackbar.show(
      context,
      message: strings.teamsSeatFull,
      variant: LimpidStatusVariant.warning,
    );
    return;
  }
  LimpidSnackbar.show(
    context,
    message: teamFailureMessage(strings, error),
    variant: LimpidStatusVariant.danger,
  );
}

/// Montre l'échec d'une action à l'auteur, et porte la cause à la console.
///
/// Une `Error` — et non une `Exception` — ne remonte pas dans un
/// `on Exception` : sans ce filet, l'échec disparaît et le bouton semble ne
/// rien faire. L'auteur voit un message, et la console porte la cause.
void _showUnexpectedFailure(
  BuildContext context,
  AppLocalizations strings,
  Object error,
  StackTrace stackTrace,
) {
  _showFailure(context, strings, error);
  debugPrint('L\'action sur l\'équipe a échoué : $error\n$stackTrace');
}
