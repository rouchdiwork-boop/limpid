import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The visibility of a book, as the interface shows it.
///
/// The publication carries **two** states (D-33): the stage of the manuscript
/// — is the book published? — and the visibility — is the book in the
/// showcase? A book can be published without being in the showcase: the
/// author finishes the manuscript and wants to read it again before it
/// reaches the readers.
enum BookVisibility {
  /// The manuscript is not published yet.
  draft,

  /// The manuscript is published, but the book is not in the showcase.
  published,

  /// The book is published and in the showcase.
  showcase;

  /// Reads the visibility of [project].
  ///
  /// The showcase is only opened by a published book: a manuscript that is
  /// not published is never in it, whatever its visibility says.
  factory BookVisibility.of(Project project) {
    if (project.status != ManuscriptStatus.published) {
      return BookVisibility.draft;
    }
    return project.isPublic
        ? BookVisibility.showcase
        : BookVisibility.published;
  }
}

/// The badge that tells the author where the book stands.
class PublicationStateBadge extends StatelessWidget {
  /// Creates the badge of a project.
  const PublicationStateBadge({required this.project, super.key});

  /// The project the badge describes.
  final Project project;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final BookVisibility visibility = BookVisibility.of(project);

    return LimpidBadge(
      label: switch (visibility) {
        BookVisibility.draft => strings.projectPublicationStateDraft,
        BookVisibility.published => strings.projectPublicationStatePublished,
        BookVisibility.showcase => strings.projectPublicationStateShowcase,
      },
      variant: switch (visibility) {
        BookVisibility.draft => LimpidStatusVariant.neutral,
        BookVisibility.published => LimpidStatusVariant.info,
        BookVisibility.showcase => LimpidStatusVariant.success,
      },
      icon: switch (visibility) {
        BookVisibility.draft => LimpidIcons.book,
        BookVisibility.published => LimpidIcons.book,
        BookVisibility.showcase => LimpidIcons.globe,
      },
    );
  }
}

/// The action that publishes a book, or takes it out of the showcase.
///
/// The action writes the **two** states of the publication (D-33): the
/// manuscript becomes published and the book becomes public. Taking a book
/// out of the showcase only withdraws the visibility — the manuscript stays
/// published.
///
/// The action goes through the repository of the manuscripts, never through
/// the network: the write is local, the synchronisation carries it to the
/// server.
class PublicationAction extends ConsumerWidget {
  /// Creates the action of a project.
  const PublicationAction({required this.project, super.key});

  /// The project the action publishes.
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final bool isInShowcase = project.isPublic;

    return LimpidButton(
      label: isInShowcase
          ? strings.projectUnpublishAction
          : strings.projectPublishAction,
      variant: LimpidButtonVariant.secondary,
      icon: isInShowcase ? LimpidIcons.close : LimpidIcons.globe,
      onPressed: () => unawaited(_apply(context, ref)),
    );
  }

  /// Asks the author to confirm, then writes the two states.
  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final bool isInShowcase = project.isPublic;
    final bool isPublication = !isInShowcase;
    final bool confirmed = await _confirm(context, isPublication);
    if (!confirmed) return;

    final ManuscriptRepository repository = ref.read(
      manuscriptRepositoryProvider,
    );
    try {
      await repository.saveProject(_published(project, isInShowcase));

      // The library is the source of the figures of the screen: it is read
      // again, and the snapshot it produces is written back, so the
      // interface shows the new state of the book without a flash of
      // loading.
      final LibrarySnapshot snapshot = await loadLibrary(repository);
      if (!context.mounted) return;
      ref.read(libraryProvider.notifier).replace(snapshot);
    } on Exception catch (error) {
      if (!context.mounted) return;
      _reportFailure(context, error);
    }
  }

  /// Builds the project the action writes.
  ///
  /// Publishing sets the two states; withdrawing only sets the visibility
  /// back — the manuscript stays published.
  static Project _published(Project project, bool isInShowcase) {
    if (isInShowcase) return project.copyWith(isPublic: false);
    return project.copyWith(status: ManuscriptStatus.published, isPublic: true);
  }

  /// Asks the author to confirm the change.
  ///
  /// Returns `true` when the author confirms, `false` when they cancel.
  Future<bool> _confirm(BuildContext context, bool isPublication) async {
    final AppLocalizations strings = AppLocalizations.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return LimpidDialog(
          title: isPublication
              ? strings.projectPublishConfirmTitle
              : strings.projectUnpublishConfirmTitle,
          actions: <Widget>[
            LimpidButton(
              label: strings.actionCancel,
              variant: LimpidButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            LimpidButton(
              label: isPublication
                  ? strings.projectPublishConfirmAction
                  : strings.projectUnpublishConfirmAction,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
          child: Text(
            isPublication
                ? strings.projectPublishConfirmMessage
                : strings.projectUnpublishConfirmMessage,
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        );
      },
    );
    return confirmed ?? false;
  }

  /// Tells the author that the publication failed.
  void _reportFailure(BuildContext context, Object error) {
    debugPrint('La publication du livre a échoué : $error');
    final AppLocalizations strings = AppLocalizations.of(context);
    LimpidSnackbar.show(
      context,
      message: strings.projectPublicationFailed,
      variant: LimpidStatusVariant.danger,
    );
  }
}
