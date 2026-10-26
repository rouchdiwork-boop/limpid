/// Les libellés des rôles d'équipe.
///
/// Les libellés vivent dans l'interface : la couche domaine ne porte que les
/// rôles, jamais les phrases que l'auteur lit.
library;

import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le libellé du rôle [role], dans la langue de l'interface.
String teamRoleLabel(AppLocalizations strings, TeamRole role) => switch (role) {
  TeamRole.owner => strings.teamsRoleOwner,
  TeamRole.coAuthor => strings.teamsRoleCoauthor,
  TeamRole.betaReader => strings.teamsRoleBeta,
  TeamRole.reader => strings.teamsRoleReader,
};

/// Le libellé de l'état d'une invitation, dans la langue de l'interface.
///
/// L'état d'une invitation n'a pas encore de chaîne à lui : l'écran emprunte
/// celles qui disent la même chose ailleurs — « En attente » pour une
/// invitation qui attend, « Expire le … » pour une invitation qui a expiré,
/// « Révoqué » pour une invitation révoquée. Les chaines propres à
/// l'invitation sont proposées au dossier : il n'y aura qu'à les préférer à
/// celles d'ici quand elles existent.
///
/// [expiresAt] est l'échéance, déjà formatée : elle ne sert qu'à l'état
/// « expirée », dont le libellé est la date.
String teamInvitationStatusLabel(
  AppLocalizations strings,
  TeamInvitationStatus status, {
  String? expiresAt,
}) {
  return switch (status) {
    TeamInvitationStatus.pending => strings.webhooksDeliveryPending,
    TeamInvitationStatus.expired => strings.shareExpiresAt(expiresAt ?? ''),
    TeamInvitationStatus.revoked => strings.shareRevokedBadge,
    TeamInvitationStatus.accepted => strings.shareLive,
  };
}

/// La variante du badge qui porte l'état d'une invitation.
///
/// L'état se lit d'un coup d'œil : une invitation qui attend est en cours,
/// une invitation révoquée est froide.
LimpidStatusVariant teamInvitationStatusVariant(TeamInvitationStatus status) {
  return switch (status) {
    TeamInvitationStatus.pending => LimpidStatusVariant.info,
    TeamInvitationStatus.accepted => LimpidStatusVariant.success,
    TeamInvitationStatus.expired => LimpidStatusVariant.warning,
    TeamInvitationStatus.revoked => LimpidStatusVariant.neutral,
  };
}
