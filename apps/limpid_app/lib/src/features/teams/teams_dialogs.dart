/// Les boîtes de dialogue des équipes.
///
/// Les dialogues vivent avec la fonctionnalité qui les possède : les écrans
/// les ouvrent, ils ne répètent pas leur construction.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_labels.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'invitation par adresse que l'auteur a préparée dans la boîte de
/// dialogue.
final class TeamEmailInviteRequest {
  /// Crée une invitation.
  const TeamEmailInviteRequest({required this.email, required this.role});

  /// L'adresse invitée.
  final String email;

  /// Le rôle accordé à l'invité.
  final TeamRole role;
}

/// L'invitation d'un compte existant que l'auteur a préparée dans la boîte
/// de dialogue.
///
/// L'invitation d'un compte **s'applique tout de suite** : le membre entre
/// dans l'équipe. L'invitation par adresse attend une réponse — les deux
/// cohabitent.
final class TeamAccountInviteRequest {
  /// Crée une invitation.
  const TeamAccountInviteRequest({required this.userId, required this.role});

  /// L'identifiant du compte invité.
  final String userId;

  /// Le rôle accordé à l'invité.
  final TeamRole role;
}

/// Demande le nom de l'équipe à créer.
///
/// Renvoie `null` quand l'auteur renonce.
Future<String?> showCreateTeamDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _CreateTeamDialog(),
  );
}

/// Demande l'adresse à inviter et le rôle qu'elle reçoit.
///
/// Renvoie `null` quand l'auteur renonce.
Future<TeamEmailInviteRequest?> showInviteByEmailDialog(
  BuildContext context,
) async {
  return showDialog<TeamEmailInviteRequest>(
    context: context,
    builder: (BuildContext context) => const _InviteByEmailDialog(),
  );
}

/// Demande le compte à inviter et le rôle qu'il reçoit.
///
/// Renvoie `null` quand l'auteur renonce.
Future<TeamAccountInviteRequest?> showInviteByAccountDialog(
  BuildContext context,
) async {
  return showDialog<TeamAccountInviteRequest>(
    context: context,
    builder: (BuildContext context) => const _InviteByAccountDialog(),
  );
}

/// Montre le lien d'une invitation, une fois.
///
/// Le lien est **copiable** : l'auteur le colle où il veut. La fenêtre
/// reste ouverte jusqu'à ce qu'il la ferme — c'est la dernière fois que le
/// lien est affiché.
Future<void> showInvitationLinkDialog(
  BuildContext context, {
  required String link,
}) {
  final AppLocalizations strings = AppLocalizations.of(context);
  return LimpidDialog.show<void>(
    context: context,
    title: strings.teamsInvite,
    icon: LimpidIcons.user,
    actions: <Widget>[
      LimpidButton(
        label: strings.shareCopy,
        icon: LimpidIcons.copy,
        variant: LimpidButtonVariant.secondary,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: link));
          if (!context.mounted) return;
          LimpidSnackbar.show(
            context,
            message: strings.shareCopied,
            variant: LimpidStatusVariant.success,
          );
        },
      ),
    ],
    builder: (BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          strings.shareLinkMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SelectableText(link, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// Demande la confirmation de la suppression de l'équipe.
///
/// Renvoie `true` quand l'auteur confirme.
Future<bool> showDeleteTeamDialog(BuildContext context) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => LimpidDialog(
      title: strings.teamsTitle,
      icon: LimpidIcons.warning,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeDialog(context, false),
        ),
        LimpidButton(
          label: strings.apiKeysDelete,
          variant: LimpidButtonVariant.danger,
          onPressed: () => _closeDialog(context, true),
        ),
      ],
      child: Text(
        strings.teamsDeleteConfirm,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );

  return confirmed ?? false;
}

/// La boîte de dialogue qui demande le nom d'une équipe.
///
/// Le champ porte son propre contrôleur : il est libéré quand la boîte
/// disparaît, pas avant.
final class _CreateTeamDialog extends StatefulWidget {
  /// Crée la boîte de dialogue.
  const _CreateTeamDialog();

  @override
  State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

/// L'état de la boîte de dialogue du nom d'équipe.
final class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  /// Le contrôleur du champ.
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return LimpidDialog(
      title: strings.teamsCreate,
      icon: LimpidIcons.add,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeDialog(context),
        ),
        LimpidButton(
          label: strings.actionCreate,
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => _closeDialog(context, _controller.text.trim()),
        ),
      ],
      child: LimpidTextField(
        controller: _controller,
        label: strings.teamsName,
        autofocus: true,
        onChanged: (String _) => setState(() {}),
        onSubmitted: (String value) {
          final String trimmed = value.trim();
          if (trimmed.isEmpty) return;
          _closeDialog(context, trimmed);
        },
      ),
    );
  }
}

/// La boîte de dialogue qui invite une adresse dans une équipe.
///
/// Le champ porte son propre contrôleur : il est libéré quand la boîte
/// disparaît, pas avant.
final class _InviteByEmailDialog extends StatefulWidget {
  /// Crée la boîte de dialogue.
  const _InviteByEmailDialog();

  @override
  State<_InviteByEmailDialog> createState() => _InviteByEmailDialogState();
}

/// L'état de la boîte de dialogue d'invitation par adresse.
final class _InviteByEmailDialogState extends State<_InviteByEmailDialog> {
  /// Le contrôleur du champ.
  final TextEditingController _controller = TextEditingController();

  /// Le rôle accordé à l'invité.
  TeamRole _role = TeamRole.coAuthor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final String email = _controller.text.trim();
    final bool canInvite = email.isNotEmpty && isValidEmail(email);

    return LimpidDialog(
      title: strings.teamsInviteEmail,
      icon: LimpidIcons.user,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeDialog(context),
        ),
        LimpidButton(
          label: strings.teamsInvite,
          onPressed: canInvite
              ? () => _closeDialog(
                  context,
                  TeamEmailInviteRequest(email: email, role: _role),
                )
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LimpidTextField(
            controller: _controller,
            label: strings.fieldEmail,
            autofocus: true,
            onChanged: (String _) => setState(() {}),
            onSubmitted: (String value) {
              final String trimmed = value.trim();
              if (!isValidEmail(trimmed)) return;
              _closeDialog(
                context,
                TeamEmailInviteRequest(email: trimmed, role: _role),
              );
            },
          ),
          SizedBox(height: context.limpid.spacing.space16),
          LimpidSelect<TeamRole>(
            label: strings.teamsRole,
            value: _role,
            items: <LimpidSelectItem<TeamRole>>[
              for (final TeamRole candidate in assignableTeamRoles)
                LimpidSelectItem<TeamRole>(
                  value: candidate,
                  label: teamRoleLabel(strings, candidate),
                ),
            ],
            onChanged: (TeamRole? selected) {
              if (selected == null) return;
              setState(() => _role = selected);
            },
          ),
        ],
      ),
    );
  }
}

/// La boîte de dialogue qui invite un compte existant dans une équipe.
///
/// Le champ porte son propre contrôleur : il est libéré quand la boîte
/// disparaît, pas avant.
final class _InviteByAccountDialog extends StatefulWidget {
  /// Crée la boîte de dialogue.
  const _InviteByAccountDialog();

  @override
  State<_InviteByAccountDialog> createState() => _InviteByAccountDialogState();
}

/// L'état de la boîte de dialogue d'invitation d'un compte.
final class _InviteByAccountDialogState extends State<_InviteByAccountDialog> {
  /// Le contrôleur du champ.
  final TextEditingController _controller = TextEditingController();

  /// Le rôle accordé à l'invité.
  TeamRole _role = TeamRole.coAuthor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final String userId = _controller.text.trim();

    return LimpidDialog(
      title: strings.teamsInvite,
      icon: LimpidIcons.user,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeDialog(context),
        ),
        LimpidButton(
          label: strings.teamsInvite,
          onPressed: userId.isEmpty
              ? null
              : () => _closeDialog(
                  context,
                  TeamAccountInviteRequest(userId: userId, role: _role),
                ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LimpidTextField(
            controller: _controller,
            label: strings.teamsInviteAccount,
            autofocus: true,
            onChanged: (String _) => setState(() {}),
            onSubmitted: (String value) {
              final String trimmed = value.trim();
              if (trimmed.isEmpty) return;
              _closeDialog(
                context,
                TeamAccountInviteRequest(userId: trimmed, role: _role),
              );
            },
          ),
          SizedBox(height: context.limpid.spacing.space16),
          LimpidSelect<TeamRole>(
            label: strings.teamsRole,
            value: _role,
            items: <LimpidSelectItem<TeamRole>>[
              for (final TeamRole candidate in assignableTeamRoles)
                LimpidSelectItem<TeamRole>(
                  value: candidate,
                  label: teamRoleLabel(strings, candidate),
                ),
            ],
            onChanged: (TeamRole? selected) {
              if (selected == null) return;
              setState(() => _role = selected);
            },
          ),
        ],
      ),
    );
  }
}

/// Ferme la boîte de dialogue, en rendant [value] quand elle en a un.
///
/// Le dialogue est posé sur le navigateur racine : les écrans vivent dans
/// une branche du shell, et une fermeture prise dans la branche ne fermerait
/// pas la boîte de dialogue.
void _closeDialog(BuildContext context, [Object? value]) {
  Navigator.of(context, rootNavigator: true).pop(value);
}
