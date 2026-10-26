import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A manuscript of the library.
///
/// The tile shows the figures of the manuscript — the words written, the
/// progress — and the stage it reached.
class LibraryTile extends StatelessWidget {
  /// Creates the tile.
  const LibraryTile({
    required this.project,
    required this.authorName,
    super.key,
  });

  /// The manuscript the tile shows.
  final ProjectSummary project;

  /// The public name of the author.
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final String status = statusLabel(strings, project.status);

    return Semantics(
      button: true,
      label: '${project.title}, $status',
      child: InkWell(
        onTap: () => context.go(AppRoutes.project(project.project.id.value)),
        borderRadius: BorderRadius.circular(scope.radii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ProjectCover(
                  title: project.title,
                  author: authorName,
                  seed: project.coverSeed,
                ),
              ),
            ),
            SizedBox(height: scope.spacing.space8),
            Text(
              project.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scope.colors.fgDefault,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: scope.spacing.space4),
            Text(
              '${strings.libraryWords(formatCount(project.wordCount))}'
              ' · ${project.progressPercent} %',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
            SizedBox(height: scope.spacing.space8),
            LimpidBadge(
              label: status,
              variant: switch (project.status) {
                ManuscriptStatus.published => LimpidStatusVariant.success,
                ManuscriptStatus.writing => LimpidStatusVariant.warning,
                _ => LimpidStatusVariant.neutral,
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The name of an editorial stage, in the language of the author.
String statusLabel(AppLocalizations strings, ManuscriptStatus status) =>
    switch (status) {
      ManuscriptStatus.writing => strings.projectStatusWriting,
      ManuscriptStatus.published => strings.projectStatusPublished,
      _ => strings.projectStatusDraft,
    };
