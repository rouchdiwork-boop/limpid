import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The card of the manuscript the author is working on.
///
/// The figures of the card — the words written, the progress — come from the
/// scenes of the manuscript.
class DashboardManuscript extends StatelessWidget {
  /// Creates the card.
  const DashboardManuscript({
    required this.project,
    required this.authorName,
    super.key,
  });

  /// The manuscript the author is working on.
  final ProjectSummary project;

  /// The public name of the author.
  final String authorName;

  /// The width of the thumbnail of the cover.
  static const double _coverWidth = 78;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return LimpidCard(
      title: strings.dashboardResumeTitle,
      trailing: LimpidBadge(
        label: _statusLabel(strings, project.status),
        variant: switch (project.status) {
          ManuscriptStatus.published => LimpidStatusVariant.success,
          ManuscriptStatus.writing => LimpidStatusVariant.warning,
          _ => LimpidStatusVariant.neutral,
        },
      ),
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProjectCover(
              title: project.title,
              author: authorName,
              seed: project.coverSeed,
              width: _coverWidth,
            ),
            SizedBox(width: scope.spacing.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    project.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scope.colors.fgDefault,
                      fontWeight: FontWeight.w600,
                      fontFamily: LimpidFontFamily.display,
                    ),
                  ),
                  SizedBox(height: scope.spacing.space4),
                  Text(
                    '${strings.libraryWords(formatCount(project.wordCount))}'
                    ' · ${project.progressPercent} %',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgMuted,
                    ),
                  ),
                  SizedBox(height: scope.spacing.space16),
                  Wrap(
                    spacing: scope.spacing.space8,
                    runSpacing: scope.spacing.space8,
                    children: <Widget>[
                      LimpidButton(
                        label: strings.dashboardResumeAction,
                        size: LimpidButtonSize.small,
                        onPressed: () => context.go(
                          AppRoutes.writing(project.project.id.value),
                        ),
                      ),
                      LimpidButton(
                        label: strings.dashboardSeePlan,
                        variant: LimpidButtonVariant.secondary,
                        icon: LimpidIcons.tree,
                        size: LimpidButtonSize.small,
                        onPressed: () => context.go(
                          AppRoutes.project(project.project.id.value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The name of an editorial stage, in the language of the author.
  static String _statusLabel(
    AppLocalizations strings,
    ManuscriptStatus status,
  ) => switch (status) {
    ManuscriptStatus.writing => strings.projectStatusWriting,
    ManuscriptStatus.published => strings.projectStatusPublished,
    _ => strings.projectStatusDraft,
  };
}
