import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_hierarchy_dialog.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The plan of the book: the series, the tomes, the chapters and their
/// scenes.
///
/// The plan is the projection of the repository: every row comes from an
/// element the repository knows about. The plan also **builds** the book:
/// every level carries the button that creates the level below it, and the
/// scenes of a chapter can be reordered.
///
/// The chapter is a *view* over its scenes (D-02): the panel shows them in
/// the order of their fractional index, and nothing else.
class WritingOutlinePanel extends StatelessWidget {
  /// Creates the plan of a project.
  const WritingOutlinePanel({
    required this.outline,
    required this.activeSceneId,
    required this.onSelectScene,
    this.onCreateSeries,
    this.onCreateVolume,
    this.onCreateChapter,
    this.onCreateScene,
    this.onMoveScene,
    super.key,
  });

  /// The outline of the project.
  final WritingOutline outline;

  /// The scene being edited, `null` when none is.
  final SceneId? activeSceneId;

  /// Called when the author picks a scene.
  final ValueChanged<OutlineScene> onSelectScene;

  /// Called with the title of the new series.
  final void Function(String title)? onCreateSeries;

  /// Called with the identifier of the series and the title of the new tome.
  final void Function(String seriesId, String title)? onCreateVolume;

  /// Called with the identifier of the tome — `null` when the chapter hangs
  /// directly on the project — and the title of the new chapter.
  final void Function(String? volumeId, String title)? onCreateChapter;

  /// Called with the identifier of the chapter and the title of the new
  /// scene.
  final void Function(String chapterId, String title)? onCreateScene;

  /// Called when the author moves a scene inside its chapter.
  ///
  /// The target is the index the scene takes, counted among the scenes of
  /// its chapter.
  final void Function(String sceneId, int targetIndex)? onMoveScene;

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
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    strings.editorOutline,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scope.colors.fgMuted,
                    ),
                  ),
                ),
                if (onCreateSeries != null)
                  _OutlineAction(
                    key: const ValueKey<String>('outline-add-series'),
                    icon: LimpidIcons.add,
                    label: strings.hierarchyAddSeries,
                    onPressed: () => _createSeries(context, strings),
                  ),
              ],
            ),
          ),
          Expanded(
            child: outline.isPlanEmpty
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
                    children: _rows(context, strings),
                  ),
          ),
        ],
      ),
    );
  }

  /// The rows of the plan, in reading order.
  List<Widget> _rows(BuildContext context, AppLocalizations strings) {
    final List<Widget> rows = <Widget>[];

    for (final OutlineSeries series in outline.series) {
      rows.add(
        _OutlineRow(
          title: series.title,
          depth: 0,
          hasChildren: true,
          trailing: onCreateVolume == null
              ? null
              : _OutlineAction(
                  key: ValueKey<String>(
                    'outline-add-volume-${series.series.id.value}',
                  ),
                  icon: LimpidIcons.add,
                  label: strings.hierarchyAddVolume,
                  onPressed: () => _createVolume(context, strings, series),
                ),
        ),
      );

      for (final OutlineVolume volume in series.volumes) {
        rows.add(
          _OutlineRow(
            title: volume.title,
            depth: 1,
            hasChildren: true,
            trailing: onCreateChapter == null
                ? null
                : _OutlineAction(
                    key: ValueKey<String>(
                      'outline-add-chapter-${volume.volume.id.value}',
                    ),
                    icon: LimpidIcons.add,
                    label: strings.hierarchyAddChapter,
                    onPressed: () => _createChapter(
                      context,
                      strings,
                      volumeId: volume.volume.id.value,
                    ),
                  ),
          ),
        );
        rows.addAll(_chapterRows(context, strings, volume.chapters));
      }
    }

    for (final OutlineChapter chapter in outline.chapters) {
      rows.addAll(_chapterRows(context, strings, <OutlineChapter>[chapter]));
    }

    if (onCreateChapter != null) {
      rows.add(
        _OutlineAction(
          key: const ValueKey<String>('outline-add-chapter-project'),
          icon: LimpidIcons.add,
          label: strings.hierarchyAddChapter,
          isWide: true,
          onPressed: () => _createChapter(context, strings, volumeId: null),
        ),
      );
    }

    return rows;
  }

  /// The rows of a chapter and of its scenes.
  List<Widget> _chapterRows(
    BuildContext context,
    AppLocalizations strings,
    List<OutlineChapter> chapters,
  ) {
    final List<Widget> rows = <Widget>[];

    for (final OutlineChapter chapter in chapters) {
      rows.add(
        _OutlineRow(
          title: chapter.title,
          depth: 2,
          hasChildren: true,
          trailing: onCreateScene == null
              ? null
              : _OutlineAction(
                  key: ValueKey<String>(
                    'outline-add-scene-${chapter.chapter.id.value}',
                  ),
                  icon: LimpidIcons.add,
                  label: strings.hierarchyAddScene,
                  onPressed: () => _createScene(context, strings, chapter),
                ),
        ),
      );

      for (int index = 0; index < chapter.scenes.length; index++) {
        rows.add(_sceneRow(strings, chapter, index));
      }
    }

    return rows;
  }

  /// The row of a scene, with the buttons that reorder it.
  Widget _sceneRow(
    AppLocalizations strings,
    OutlineChapter chapter,
    int index,
  ) {
    final OutlineScene scene = chapter.scenes[index];
    final bool isFirst = index == 0;
    final bool isLast = index == chapter.scenes.length - 1;

    return _OutlineRow(
      title: scene.title,
      depth: 3,
      wordCount: scene.wordCount,
      isActive: scene.id == activeSceneId,
      onTap: () => onSelectScene(scene),
      trailing: onMoveScene == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _OutlineAction(
                  key: ValueKey<String>('outline-move-up-${scene.id.value}'),
                  icon: LimpidIcons.chevronUp,
                  label: strings.hierarchyMoveUp,
                  isEnabled: !isFirst,
                  onPressed: () => onMoveScene!(scene.id.value, index - 1),
                ),
                _OutlineAction(
                  key: ValueKey<String>('outline-move-down-${scene.id.value}'),
                  icon: LimpidIcons.chevronDown,
                  label: strings.hierarchyMoveDown,
                  isEnabled: !isLast,
                  onPressed: () => onMoveScene!(scene.id.value, index + 1),
                ),
              ],
            ),
    );
  }

  /// Asks for the title of the new series and hands it over.
  Future<void> _createSeries(
    BuildContext context,
    AppLocalizations strings,
  ) async {
    final void Function(String title)? create = onCreateSeries;
    if (create == null) return;
    final String? title = await showHierarchyTitleDialog(
      context: context,
      title: strings.hierarchyAddSeries,
    );
    if (title == null || title.isEmpty) return;
    create(title);
  }

  /// Asks for the title of the new tome and hands it over.
  Future<void> _createVolume(
    BuildContext context,
    AppLocalizations strings,
    OutlineSeries series,
  ) async {
    final void Function(String seriesId, String title)? create = onCreateVolume;
    if (create == null) return;
    final String? title = await showHierarchyTitleDialog(
      context: context,
      title: strings.hierarchyAddVolume,
    );
    if (title == null || title.isEmpty) return;
    create(series.series.id.value, title);
  }

  /// Asks for the title of the new chapter and hands it over.
  Future<void> _createChapter(
    BuildContext context,
    AppLocalizations strings, {
    required String? volumeId,
  }) async {
    final void Function(String? volumeId, String title)? create =
        onCreateChapter;
    if (create == null) return;
    final String? title = await showHierarchyTitleDialog(
      context: context,
      title: strings.hierarchyAddChapter,
    );
    if (title == null || title.isEmpty) return;
    create(volumeId, title);
  }

  /// Asks for the title of the new scene and hands it over.
  Future<void> _createScene(
    BuildContext context,
    AppLocalizations strings,
    OutlineChapter chapter,
  ) async {
    final void Function(String chapterId, String title)? create = onCreateScene;
    if (create == null) return;
    final String? title = await showHierarchyTitleDialog(
      context: context,
      title: strings.hierarchyAddScene,
    );
    if (title == null || title.isEmpty) return;
    create(chapter.chapter.id.value, title);
  }
}

/// A row of the plan: the title of an element and its action.
class _OutlineRow extends StatelessWidget {
  /// Creates a row of the plan.
  const _OutlineRow({
    required this.title,
    required this.depth,
    this.wordCount,
    this.isActive = false,
    this.hasChildren = false,
    this.onTap,
    this.trailing,
  });

  /// The label of the row.
  final String title;

  /// The depth of the row in the hierarchy, starting at 0.
  final int depth;

  /// The number of words of the row.
  final int? wordCount;

  /// Whether the row is the one being edited.
  final bool isActive;

  /// Whether the row has children.
  final bool hasChildren;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  /// The action the row carries.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: LimpidOutlineRow(
            title: title,
            depth: depth,
            wordCount: wordCount,
            hasChildren: hasChildren,
            isActive: isActive,
            onTap: onTap,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// The button that adds an element of the hierarchy, or that moves one.
class _OutlineAction extends StatelessWidget {
  /// Creates an action of the plan.
  const _OutlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.isWide = false,
  });

  /// The icon of the action.
  final IconData icon;

  /// The label announced par l'écran reader.
  final String label;

  /// Called when the author presses the action.
  final VoidCallback onPressed;

  /// Whether the action reacts to the pointer.
  final bool isEnabled;

  /// Whether the action shows its label beside its icon.
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    if (isWide) {
      return Padding(
        padding: EdgeInsets.only(
          left: scope.spacing.space8,
          top: scope.spacing.space4,
        ),
        child: LimpidButton(
          label: label,
          icon: icon,
          variant: LimpidButtonVariant.ghost,
          size: LimpidButtonSize.small,
          onPressed: onPressed,
        ),
      );
    }

    return IconButton(
      onPressed: isEnabled ? onPressed : null,
      tooltip: label,
      iconSize: 18,
      icon: Icon(icon, color: scope.colors.fgMuted),
    );
  }
}
