/// Le partage en lecture d'un livre.
///
/// La section montre les liens que l'auteur a déjà partagés, lui permet d'en
/// créer un, et de révoquer ceux qui ne doivent plus ouvrir le livre.
///
/// Le lien n'est montré **qu'une fois**, à sa création : le serveur n'en
/// garde que l'empreinte.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/share_repository.dart';
import 'package:limpid_app/src/features/project/share_actions.dart';
import 'package:limpid_app/src/features/project/share_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La section du partage en lecture, dans l'écran d'un livre.
class ShareSection extends ConsumerWidget {
  /// Crée la section.
  const ShareSection({required this.projectId, super.key});

  /// Le livre partagé.
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final AsyncValue<List<Share>> state = ref.watch(accountSharesProvider);
    final List<Share> shares = ref.watch(projectSharesProvider(projectId));

    return LimpidCard(
      title: strings.shareTitle,
      subtitle: strings.shareSubtitle,
      trailing: LimpidButton(
        label: strings.shareCreate,
        icon: LimpidIcons.externalLink,
        size: LimpidButtonSize.small,
        onPressed: () =>
            unawaited(createShare(context, ref, projectId: projectId)),
      ),
      child: _body(context, ref, state, shares),
    );
  }

  /// Le corps de la section : les partages, ou l'état qui explique pourquoi
  /// il n'y en a pas.
  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Share>> state,
    List<Share> shares,
  ) {
    final AppLocalizations strings = AppLocalizations.of(context);

    if (state.isLoading) {
      return const LimpidSpinner(size: LimpidSpinnerSize.medium);
    }
    if (state.hasError) {
      return Row(
        children: <Widget>[
          Expanded(child: Text(strings.shareUnavailable)),
          LimpidButton(
            label: strings.actionRetry,
            icon: LimpidIcons.sync,
            variant: LimpidButtonVariant.ghost,
            size: LimpidButtonSize.small,
            onPressed: () => ref.invalidate(accountSharesProvider),
          ),
        ],
      );
    }
    if (shares.isEmpty) {
      return Text(strings.shareEmpty);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final Share share in shares) ...<Widget>[
          _ShareRow(share: share),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Un partage, avec son état et sa révocation.
class _ShareRow extends ConsumerWidget {
  /// Crée la ligne.
  const _ShareRow({required this.share});

  /// Le partage montré.
  final Share share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(share.expiresAt.toLocal());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        LimpidBadge(
          label: share.isRevoked
              ? strings.shareRevokedBadge
              : strings.shareLive,
          variant: share.isRevoked
              ? LimpidStatusVariant.neutral
              : LimpidStatusVariant.success,
        ),
        SizedBox(width: scope.spacing.space12),
        Expanded(
          child: Text(
            strings.shareExpiresAt(date),
            style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
        if (!share.isRevoked)
          LimpidButton(
            label: strings.shareRevoke,
            variant: LimpidButtonVariant.ghost,
            size: LimpidButtonSize.small,
            onPressed: () =>
                unawaited(revokeShare(context, ref, shareId: share.id)),
          ),
      ],
    );
  }
}
