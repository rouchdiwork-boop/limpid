import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/project/publication_action.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/projects_controller.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The overview of a single project.
class ProjectScreen extends ConsumerWidget {
  /// Creates the screen.
  const ProjectScreen({required this.projectId, super.key});

  /// The identifier of the project.
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = context.limpid;
    final projects = ref.watch(projectsControllerProvider);
    final project = projects.firstWhere(
      (item) => item.project.id.value == projectId,
      orElse: () => projects.first,
    );

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 820;
              final cover = ProjectCover(
                title: project.title,
                author: 'Aurélien Sandre',
                seed: project.coverSeed,
                width: 132,
              );
              final header = _ProjectHeader(project: project);

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    cover,
                    SizedBox(height: scope.spacing.space20),
                    header,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  cover,
                  SizedBox(width: scope.spacing.space24),
                  Expanded(child: header),
                ],
              );
            },
          ),
          SizedBox(height: scope.spacing.space24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final chapters = _ChaptersCard(
                project: project,
                chapters: ref.watch(projectChaptersProvider(projectId)),
              );
              final side = _MetadataCard(project: project);

              if (!isWide) {
                return Column(
                  children: <Widget>[
                    chapters,
                    SizedBox(height: scope.spacing.space20),
                    side,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 60, child: chapters),
                  SizedBox(width: scope.spacing.space20),
                  Expanded(flex: 40, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            LimpidBadge(
              label: project.status == ManuscriptStatus.writing
                  ? strings.projectStatusWriting
                  : project.status == ManuscriptStatus.published
                  ? strings.projectStatusPublished
                  : strings.projectStatusDraft,
              variant: project.status == ManuscriptStatus.published
                  ? LimpidStatusVariant.success
                  : project.status == ManuscriptStatus.writing
                  ? LimpidStatusVariant.warning
                  : LimpidStatusVariant.neutral,
            ),
            LimpidBadge(
              label: strings.projectChapterCount(project.chapterCount),
            ),
            PublicationStateBadge(project: project.project),
          ],
        ),
        SizedBox(height: scope.spacing.space12),
        Text(
          project.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
            fontFamily: LimpidFontFamily.display,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          project.synopsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scope.colors.fgMuted,
            fontFamily: LimpidFontFamily.manuscript,
            height: 1.7,
          ),
        ),
        SizedBox(height: scope.spacing.space20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            LimpidButton(
              label: strings.projectContinueWriting,
              icon: LimpidIcons.pen,
              onPressed: () =>
                  context.go(AppRoutes.writing(project.project.id.value)),
            ),
            LimpidButton(
              label: strings.projectExport,
              variant: LimpidButtonVariant.secondary,
              icon: LimpidIcons.export,
            ),
            LimpidButton(
              label: strings.projectPublicPage,
              variant: LimpidButtonVariant.secondary,
              icon: LimpidIcons.globe,
            ),
            PublicationAction(project: project.project),
          ],
        ),
        SizedBox(height: scope.spacing.space20),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.projectProgress,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scope.colors.fgSubtle,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LimpidLinearProgress(value: project.progress),
                  const SizedBox(height: 6),
                  Text(
                    '${_format(project.wordCount)} / ${_format(project.targetWordCount)} mots · ${project.progressPercent} % ${strings.projectProgressOf}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChaptersCard extends StatelessWidget {
  const _ChaptersCard({required this.project, required this.chapters});

  final ProjectSummary project;

  /// The chapters of the project, with the number of words they hold.
  final AsyncValue<List<(Chapter, int)>> chapters;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;
    final List<(Chapter, int)> items =
        chapters.value ?? const <(Chapter, int)>[];

    return LimpidCard(
      title: strings.projectChaptersTitle,
      trailing: LimpidButton(
        label: strings.actionCreate,
        variant: LimpidButtonVariant.ghost,
        icon: LimpidIcons.add,
        size: LimpidButtonSize.small,
      ),
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space12),
        child: Column(
          children: <Widget>[
            for (int index = 0; index < items.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scope.colors.fgSubtle,
                          fontFamily: LimpidFontFamily.mono,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        items[index].$1.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scope.colors.fgDefault,
                        ),
                      ),
                    ),
                    LimpidBadge(
                      label: switch (items[index].$1.status) {
                        ManuscriptStatus.review =>
                          strings.projectChapterStateDone,
                        ManuscriptStatus.writing =>
                          strings.projectChapterStateDraft,
                        _ => strings.projectChapterStateTodo,
                      },
                      variant: switch (items[index].$1.status) {
                        ManuscriptStatus.review => LimpidStatusVariant.success,
                        ManuscriptStatus.writing => LimpidStatusVariant.warning,
                        _ => LimpidStatusVariant.neutral,
                      },
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 74,
                      child: Text(
                        _format(items[index].$2),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scope.colors.fgMuted,
                          fontFamily: LimpidFontFamily.mono,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;

    return LimpidCard(
      title: strings.projectMetadataTitle,
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space12),
        child: Column(
          children: <Widget>[
            for (final entry in <(String, String)>[
              (strings.projectMetadataIsbn, '978‑2‑4915‑0382‑7'),
              (strings.projectMetadataFormat, 'EPUB 3 + PDF'),
              (strings.projectMetadataLanguage, 'Français'),
              (strings.projectMetadataPrice, '8,90 €'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.$1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scope.colors.fgMuted,
                        ),
                      ),
                    ),
                    Text(
                      entry.$2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scope.colors.fgDefault,
                        fontFamily: LimpidFontFamily.mono,
                      ),
                    ),
                  ],
                ),
              ),
            LimpidButton(
              label: strings.projectMetadataTitle,
              variant: LimpidButtonVariant.secondary,
              size: LimpidButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a number with thin spaces between thousands.
String _format(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
