import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/projects_controller.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The entry of the writing destination.
///
/// The branch needs a non-parameterised default route, so this screen lists
/// the books the author can open in the editor.
class ProjectPickerScreen extends ConsumerWidget {
  /// Creates the screen.
  const ProjectPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;
    final projects = ref.watch(projectsControllerProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          Text(
            strings.writingTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontWeight: FontWeight.w600,
              fontFamily: LimpidFontFamily.display,
            ),
          ),
          SizedBox(height: scope.spacing.space4),
          Text(
            'Choisissez le livre à ouvrir.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space20),
          for (final project in projects)
            Padding(
              padding: EdgeInsets.only(bottom: scope.spacing.space12),
              child: LimpidCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () =>
                      context.go(AppRoutes.writing(project.project.id.value)),
                  borderRadius: BorderRadius.circular(scope.radii.lg),
                  child: Padding(
                    padding: EdgeInsets.all(scope.spacing.space16),
                    child: Row(
                      children: <Widget>[
                        ProjectCover(
                          title: project.title,
                          author: 'Aurélien Sandre',
                          seed: project.coverSeed,
                          width: 52,
                        ),
                        SizedBox(width: scope.spacing.space16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                project.title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: scope.colors.fgDefault,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${project.chapterCount} chapitres · '
                                '${project.sceneCount} scènes · '
                                '${project.progressPercent} %',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scope.colors.fgMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          LimpidIcons.chevronRight,
                          size: 18,
                          color: scope.colors.fgSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
