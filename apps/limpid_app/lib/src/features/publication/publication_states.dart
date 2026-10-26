import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The state of a public page while the book is being read.
class PublicationLoading extends StatelessWidget {
  /// Creates the state.
  const PublicationLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space80),
      child: const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
    );
  }
}

/// The state of a public page when the book could not be read.
class PublicationFailure extends StatelessWidget {
  /// Creates the state.
  const PublicationFailure({required this.onRetry, super.key});

  /// Called when the reader asks for the book again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.errorGeneric,
        message: strings.dataEmptyMessage,
        icon: LimpidIcons.error,
        action: LimpidButton(
          label: strings.actionRetry,
          icon: LimpidIcons.sync,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

/// The state of a book that has no public page.
///
/// A book that is not published yet — and a book that does not exist at all —
/// have no page to show. The state says it explicitly instead of displaying
/// an empty shell that looks like a book without chapters.
class PublicationUnavailable extends StatelessWidget {
  /// Creates the state.
  const PublicationUnavailable({this.project, super.key});

  /// The manuscript behind the missing page, `null` when it does not exist.
  final Project? project;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final Project? book = project;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.publicationNotPublished,
        message: strings.publicationNotPublishedMessage,
        icon: LimpidIcons.globe,
        action: book == null
            ? null
            : LimpidBadge(
                label: publicationStatusLabel(strings, book.status),
                variant: publicationStatusVariant(book.status),
              ),
      ),
    );
  }
}

/// The label of an editorial stage, in the language of the interface.
String publicationStatusLabel(
  AppLocalizations strings,
  ManuscriptStatus status,
) {
  return switch (status) {
    ManuscriptStatus.published => strings.projectStatusPublished,
    ManuscriptStatus.writing => strings.projectStatusWriting,
    _ => strings.projectStatusDraft,
  };
}

/// The variant of the badge carrying an editorial stage.
LimpidStatusVariant publicationStatusVariant(ManuscriptStatus status) {
  return switch (status) {
    ManuscriptStatus.published => LimpidStatusVariant.success,
    ManuscriptStatus.writing => LimpidStatusVariant.warning,
    _ => LimpidStatusVariant.neutral,
  };
}
