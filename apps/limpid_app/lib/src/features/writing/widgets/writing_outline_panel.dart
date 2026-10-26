import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The plan of the book: the chapters and their scenes.
///
/// The plan is the projection of the repository: every row comes from a
/// scene the repository knows about.
class WritingOutlinePanel extends StatelessWidget {
  /// Creates the plan of a project.
  const WritingOutlinePanel({
    required this.outline,
    required this.activeSceneId,
    required this.onSelectScene,
    super.key,
  });

  /// The outline of the project.
  final WritingOutline outline;

  /// The scene being edited, `null` when none is.
  final SceneId? activeSceneId;

  /// Called when the author picks a scene.
  final ValueChanged<OutlineScene> onSelectScene;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return ColoredBox(
      color: scope.colors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              scope.spacing.space16,
              scope.spacing.space12,
              scope.spacing.space16,
              scope.spacing.space8,
            ),
            child: Text(
              strings.editorOutline,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scope.colors.fgMuted),
            ),
          ),
          Expanded(
            child: outline.isEmpty
                ? LimpidEmptyState(
                    title: strings.editorOutlineEmpty,
                    icon: LimpidIcons.tree,
                  )
                : ListView(
                    padding: EdgeInsets.only(
                      left: scope.spacing.space8,
                      right: scope.spacing.space8,
                      bottom: scope.spacing.space16,
                    ),
                    children: <Widget>[
                      for (final OutlineChapter chapter in outline.chapters)
                        _ChapterBlock(
                          chapter: chapter,
                          activeSceneId: activeSceneId,
                          onSelectScene: onSelectScene,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A chapter of the plan and the scenes it holds.
class _ChapterBlock extends StatelessWidget {
  const _ChapterBlock({
    required this.chapter,
    required this.activeSceneId,
    required this.onSelectScene,
  });

  final OutlineChapter chapter;
  final SceneId? activeSceneId;
  final ValueChanged<OutlineScene> onSelectScene;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LimpidOutlineRow(
          title: chapter.title,
          depth: 0,
          hasChildren: true,
          isExpanded: true,
        ),
        for (final OutlineScene scene in chapter.scenes)
          LimpidOutlineRow(
            title: scene.title,
            depth: 1,
            wordCount: scene.wordCount,
            isActive: scene.id == activeSceneId,
            onTap: () => onSelectScene(scene),
          ),
      ],
    );
  }
}
