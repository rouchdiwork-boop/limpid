import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/features/actions/remote_runner.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_metadata_form.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_routes.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Prépare un dossier de publication et ouvre l'écran du dépôt.
///
/// Le formulaire est une boîte de dialogue : il se referme quand le dossier
/// est prêt, et l'écran montre ensuite le dépôt — celui qu'on vient de
/// préparer, ou celui qu'on vient de corriger et de redéposer.
///
/// Le dossier corrigé est un dossier **nouveau** : le serveur garde les
/// métadonnées d'une publication, il ne les modifie pas. L'historique montre
/// donc les deux dépôts — le refusé et le corrigé.
///
/// La préparation et le dépôt vont au serveur : ils passent par la fenêtre
/// du second facteur, et sont répétés quand le serveur refuse la preuve. Le
/// dossier refusé n'a jamais été préparé : la répétition n'en prépare
/// qu'un.
Future<void> prepareKdpSubmission(
  BuildContext context,
  WidgetRef ref, {
  KdpSubmission? initial,
  bool retry = false,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final RemoteRunner runner = remoteRunnerOf(context, ref);
  KdpSubmission? prepared;
  await LimpidDialog.show<void>(
    context: context,
    title: initial == null ? strings.kdpCreate : strings.kdpFixAndRetry,
    builder: (BuildContext dialogContext) => KdpMetadataForm(
      initial: initial,
      submitLabel: initial == null
          ? strings.kdpPrepare
          : strings.kdpFixAndRetry,
      onSubmit: (KdpMetadata metadata, String projectId) async {
        final KdpSubmission submission = await runner(
          () => ref
              .read(kdpRepositoryProvider)
              .prepare(projectId: projectId, metadata: metadata),
        );
        prepared = submission;
        ref.invalidate(kdpSubmissionsProvider);
        if (retry) {
          await ref
              .read(kdpDepositProvider.notifier)
              .submit(submission.id, runner: runner);
        }
      },
      onCompleted: () => Navigator.of(dialogContext).pop(),
    ),
  );

  final KdpSubmission? result = prepared;
  if (result == null || !context.mounted) return;
  unawaited(context.push(KdpRoutes.submission(result.id)));
}

/// Dépose le dossier [submissionId] auprès d'Amazon.
///
/// Le dépôt est rendu dans tous les cas : l'écran montre le verdict
/// d'Amazon, ou dit que le livre n'est pas parti.
///
/// Le dépôt va au serveur : il passe par la fenêtre du second facteur.
Future<void> depositKdpSubmission(
  BuildContext context,
  WidgetRef ref,
  String submissionId,
) async {
  await ref
      .read(kdpDepositProvider.notifier)
      .submit(submissionId, runner: remoteRunnerOf(context, ref));
}
