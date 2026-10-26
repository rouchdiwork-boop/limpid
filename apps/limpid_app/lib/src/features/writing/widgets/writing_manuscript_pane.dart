import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_selected_passage.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// The letter spacing of the scene label, in logical pixels.
const double _letterSpacing = 0.8;

/// The action of the pane when there is nothing to close.
void _closeNothing() {}

/// The manuscript of a project: the scene being written.
///
/// The pane hosts the editor of `limpid_quill`: the text lives in the editor,
/// the operations it produces are handed over to the controller, which writes
/// them through the repository. The comments anchored on the manuscript are
/// handed over as well: the editor marks the passages they cover, and the
/// selected one is shown in relief above the text.
class WritingManuscriptPane extends StatelessWidget {
  /// Creates the manuscript pane.
  const WritingManuscriptPane({
    required this.scene,
    required this.authorId,
    required this.blocks,
    required this.isDocumentLoading,
    required this.lamport,
    required this.isReadMode,
    required this.onChanged,
    this.commentAnchors = const <LimpidCommentAnchor>[],
    this.selectedAnchor,
    this.onSelectAnchor,
    this.onClearSelection,
    super.key,
  });

  /// The scene being written, `null` when no scene is opened.
  final OutlineScene? scene;

  /// The author stamping the operations.
  final AuthorId authorId;

  /// The CRDT blocks backing the lines of the scene.
  final List<SceneBlock> blocks;

  /// Whether the document of the scene is still being read.
  ///
  /// The editor takes the state of the document **once**, when it is built.
  /// Building it before the document arrives would show an empty manuscript
  /// that never fills up: the pane waits instead.
  final bool isDocumentLoading;

  /// The Lamport timestamp of the last operation applied locally.
  final int lamport;

  /// Whether the manuscript is displayed instead of being edited.
  final bool isReadMode;

  /// Called with the operations every change produced.
  final ValueChanged<List<SyncOp>> onChanged;

  /// The comments anchored on the manuscript.
  final List<LimpidCommentAnchor> commentAnchors;

  /// The anchor the author selected, `null` when nothing is selected.
  final LimpidCommentAnchor? selectedAnchor;

  /// Called when the author selects the range of a comment.
  final ValueChanged<LimpidCommentAnchor>? onSelectAnchor;

  /// Called when the author closes the selected passage.
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final OutlineScene? current = scene;

    if (current == null) {
      return ColoredBox(
        color: scope.colors.bgCanvas,
        child: LimpidEmptyState(
          title: strings.editorOutlineEmpty,
          icon: LimpidIcons.pen,
        ),
      );
    }

    final String? excerpt = _excerptOfSelectedAnchor();

    return ColoredBox(
      color: scope.colors.bgCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              scope.spacing.space24,
              scope.spacing.space16,
              scope.spacing.space24,
              scope.spacing.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  strings.writingSceneLabel(
                    '${current.chapterNumber}',
                    '${current.sceneNumber}',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scope.colors.fgSubtle,
                    letterSpacing: _letterSpacing,
                  ),
                ),
                SizedBox(height: scope.spacing.space6),
                Text(
                  current.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (selectedAnchor != null && excerpt != null)
            WritingSelectedPassage(
              anchor: selectedAnchor!,
              excerpt: excerpt,
              onClose: onClearSelection ?? _closeNothing,
            ),
          Expanded(
            child: isDocumentLoading
                ? const Center(child: LimpidSpinner())
                : LimpidSceneEditor(
                    key: ValueKey<String>('scene-${current.id.value}'),
                    sceneId: current.id,
                    authorId: authorId,
                    documentId: current.documentId,
                    initialBlocks: blocks,
                    readOnly: isReadMode,
                    mode: isReadMode
                        ? LimpidSceneEditorMode.readOnly
                        : LimpidSceneEditorMode.writing,
                    lamport: lamport,
                    commentAnchors: commentAnchors,
                    onSelectCommentRange: onSelectAnchor,
                    onChanged: onChanged,
                  ),
          ),
        ],
      ),
    );
  }

  /// The text covered by the selected anchor, in the text of the scene.
  String? _excerptOfSelectedAnchor() {
    final LimpidCommentAnchor? anchor = selectedAnchor;
    if (anchor == null) {
      return null;
    }
    final String text = _sceneTextOf();
    final MarkRange range = anchor.range;
    if (range.start >= text.length) {
      return '';
    }
    final int end = range.end > text.length ? text.length : range.end;
    return text.substring(range.start, end);
  }

  /// The text of the scene, laid out as the editor lays it out.
  String _sceneTextOf() {
    final StringBuffer buffer = StringBuffer();
    for (final SceneBlock block in blocks) {
      buffer.write(block.plainText);
      buffer.write('\n');
    }
    return buffer.toString();
  }
}
