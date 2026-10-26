/// Les actions du partage en lecture d'un livre.
///
/// Elles vivent à part de la page : la page dessine, les actions décident.
/// Une action qui échoue le dit à l'auteur — elle ne fait jamais semblant
/// qu'un lien a été partagé, ni qu'un partage a été révoqué.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/dependencies.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/share_repository.dart';
import 'package:limpid_app/src/features/project/share_providers.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Partage le livre [projectId] en lecture et montre son lien.
///
/// Le lien est montré **une seule fois** : le serveur ne rend plus jamais le
/// jeton, et l'application ne le garde pas. La création va au serveur : elle
/// passe par la fenêtre du second facteur.
Future<void> createShare(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    final CreatedShare created = await runWithTwoFactor(
      context,
      ref,
      action: () =>
          ref.read(shareRepositoryProvider).createShare(projectId: projectId),
    );
    if (!context.mounted) return;
    ref.invalidate(accountSharesProvider);
    await _showTheLink(context, strings, shareDocumentUri(created.token));
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    debugPrint('Le partage n\'a pas pu être créé : $error\n$stackTrace');
  }
}

/// Révoque le partage [shareId].
///
/// La révocation va au serveur : elle passe par la fenêtre du second
/// facteur. Un partage révoqué n'ouvre plus rien : le lien répond une erreur
/// comme un lien qui n'a jamais existé.
Future<void> revokeShare(
  BuildContext context,
  WidgetRef ref, {
  required String shareId,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  try {
    await runWithTwoFactor(
      context,
      ref,
      action: () => ref.read(shareRepositoryProvider).revokeShare(shareId),
    );
  } on Exception catch (error) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    return;
  } on Object catch (error, stackTrace) {
    if (!context.mounted) return;
    _showFailure(context, strings, error);
    debugPrint('Le partage n\'a pas pu être révoqué : $error\n$stackTrace');
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(accountSharesProvider);
  LimpidSnackbar.show(
    context,
    message: strings.shareRevoked,
    variant: LimpidStatusVariant.success,
  );
}

/// L'adresse publique du document partagé avec [token].
///
/// Le lien ne donne aucun droit d'écriture : il ouvre le document, rien
/// d'autre.
Uri shareDocumentUri(String token) {
  final Uri base = Uri.parse(apiBaseUrl);
  final String path = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(path: '$path/v1/public/shares/$token/document');
}

/// Montre le lien du partage, une fois.
///
/// Le lien est **copiable** : l'auteur le colle où il veut. La fenêtre
/// reste ouverte jusqu'à ce qu'il la ferme — c'est la dernière fois que le
/// lien est affiché.
Future<void> _showTheLink(
  BuildContext context,
  AppLocalizations strings,
  Uri link,
) {
  return LimpidDialog.show<void>(
    context: context,
    title: strings.shareLinkTitle,
    icon: LimpidIcons.externalLink,
    actions: <Widget>[
      LimpidButton(
        label: strings.shareCopy,
        icon: LimpidIcons.copy,
        variant: LimpidButtonVariant.secondary,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: link.toString()));
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
        SelectableText(
          link.toString(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// Montre l'échec d'une action à l'auteur.
///
/// Le serveur écrit ses messages en français, à destination de l'auteur :
/// l'écran les montre quand il en a un. Les autres échecs — un service
/// absent, un réseau coupé — gardent le message générique de l'interface.
void _showFailure(
  BuildContext context,
  AppLocalizations strings,
  Object error,
) {
  final String message = error is ApiException && error.message.isNotEmpty
      ? error.message
      : strings.shareFailure;
  LimpidSnackbar.show(
    context,
    message: message,
    variant: LimpidStatusVariant.danger,
  );
}
