import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/editor/selection_ranges.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_comment_dialog.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_selected_passage.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_selection_bar.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// L'espacement des lettres de l'étiquette de la scène, en pixels logiques.
const double _letterSpacing = 0.8;

/// L'action de la bande quand il n'y a rien à fermer.
void _closeNothing() {}

/// Le manuscrit d'un projet : la scène en cours d'écriture.
///
/// La bande héberge l'éditeur de `limpid_quill` : le texte vit dans l'éditeur,
/// les opérations qu'il produit sont remises au contrôleur, qui les écrit
/// par le dépôt. Les commentaires ancrés sur le manuscrit lui sont remis
/// aussi : l'éditeur marque les passages qu'ils couvrent, et celui qui est
/// sélectionné est montré en relief au-dessus du texte.
///
/// Le bande tient aussi le **contrôleur de l'éditeur** : c'est lui qui sait
/// quel passage l'auteur a sélectionné, et c'est par lui que la sélection
/// est ramenée au bloc qu'elle appartient.
class WritingManuscriptPane extends StatefulWidget {
  /// Crée la bande du manuscrit.
  const WritingManuscriptPane({
    required this.scene,
    required this.authorId,
    required this.blocks,
    required this.isDocumentLoading,
    required this.lamport,
    required this.isReadMode,
    required this.onChanged,
    required this.onComment,
    this.commentAnchors = const <LimpidCommentAnchor>[],
    this.selectedAnchor,
    this.onSelectAnchor,
    this.onClearSelection,
    this.onCursorMoved,
    this.remoteOperations = const <SyncOp>[],
    super.key,
  });

  /// La scène en cours d'écriture, `null` quand aucune scène n'est ouverte.
  final OutlineScene? scene;

  /// L'auteur qui estampille les opérations.
  final AuthorId authorId;

  /// Les blocs CRDT qui portent les lignes de la scène.
  final List<SceneBlock> blocks;

  /// Le document de la scène est-il encore en lecture ?
  ///
  /// L'éditeur prend l'état du document **une fois**, quand il est
  /// construit. Le construire avant l'arrivée du document montrerait un
  /// manuscrit vide qui ne se remplirait jamais : la bande attend donc.
  final bool isDocumentLoading;

  /// Le timestamp Lamport de la dernière opération appliquée localement.
  final int lamport;

  /// Le manuscrit est-il affiché au lieu d'être édité ?
  final bool isReadMode;

  /// Appelé avec les opérations que chaque changement a produites.
  final ValueChanged<List<SyncOp>> onChanged;

  /// Appelé quand l'auteur commente le passage qu'il a sélectionné.
  ///
  /// Le rappel reçoit le passage — le bloc, sa plage et les mots commentés —
  /// et le message de l'auteur.
  final void Function(SelectedPassage passage, String body) onComment;

  /// Les commentaires ancrés sur le manuscrit.
  final List<LimpidCommentAnchor> commentAnchors;

  /// L'ancre sélectionnée, `null` quand rien n'est sélectionné.
  final LimpidCommentAnchor? selectedAnchor;

  /// Appelé quand l'auteur sélectionne la plage d'un commentaire.
  final ValueChanged<LimpidCommentAnchor>? onSelectAnchor;

  /// Appelé quand l'auteur ferme le passage sélectionné.
  final VoidCallback? onClearSelection;

  /// Appelé quand le curseur de l'auteur a bougé.
  ///
  /// Le rappel reçoit le bloc où se trouve le curseur et le décalage du
  /// curseur dans ce bloc : la présence du relais l'annonce aux autres
  /// auteurs.
  final void Function(String blockId, int offset)? onCursorMoved;

  /// Les opérations qu'un autre auteur a produites.
  ///
  /// L'éditeur les applique au manuscrit qu'il montre : le texte de l'autre
  /// auteur apparaît sans que l'auteur perde son curseur.
  final List<SyncOp> remoteOperations;

  @override
  State<WritingManuscriptPane> createState() => _WritingManuscriptPaneState();
}

/// L'état de la bande du manuscrit.
class _WritingManuscriptPaneState extends State<WritingManuscriptPane> {
  /// Le contrôleur de l'éditeur : il porte le texte de la scène et la
  /// sélection de l'auteur.
  late final LimpidManuscriptController _manuscript;

  /// La clé du texte que le contrôleur porte : elle change quand le
  /// manuscrit est (re)chargé.
  late String _loadedKey;

  @override
  void initState() {
    super.initState();
    _manuscript = LimpidManuscriptController.ofBlocks(
      widget.blocks,
      onChange: _onSelectionChanged,
    );
    _loadedKey = _editorKey();
  }

  @override
  void didUpdateWidget(WritingManuscriptPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadTheText();
  }

  @override
  void dispose() {
    _manuscript.dispose();
    super.dispose();
  }

  /// Charge le texte de la scène quand l'éditeur va être construit.
  ///
  /// L'éditeur prend l'état du document **une fois**, quand il est
  /// construit : le contrôleur doit donc porter exactement le même texte.
  void _loadTheText() {
    final String key = _editorKey();
    if (key == _loadedKey) {
      return;
    }
    _loadedKey = key;
    _manuscript.load(widget.blocks);
  }

  /// La clé de l'éditeur de la scène.
  ///
  /// Elle change quand le texte de la scène arrive : l'éditeur est alors
  /// construit, et il prend le texte que le contrôleur porte.
  String _editorKey() {
    final OutlineScene? scene = widget.scene;
    if (scene == null) {
      return 'scene-';
    }
    final String state = widget.isDocumentLoading ? 'loading' : 'ready';
    return 'scene-${scene.id.value}-$state';
  }

  /// Annonce la sélection de l'auteur : la bande propose de commenter le
  /// passage qu'il a choisi.
  void _onSelectionChanged(LimpidEditorSelection selection) {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  /// Le passage que l'auteur a sélectionné, `null` quand il n'a rien
  /// sélectionné ou quand sa sélection traverse deux blocs.
  SelectedPassage? _selectedPassage() {
    final LimpidEditorSelection selection = _manuscript.selection;
    if (selection.isEmpty) {
      return null;
    }
    return selectedPassageOf(
      blocks: widget.blocks,
      start: selection.start,
      end: selection.end,
    );
  }

  /// Demande le message du commentaire et le remet à l'écran.
  Future<void> _comment(SelectedPassage passage) async {
    final String? body = await showCommentComposer(
      context,
      excerpt: passage.text,
    );
    if (body == null || body.trim().isEmpty || !mounted) {
      return;
    }
    widget.onComment(passage, body.trim());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final OutlineScene? current = widget.scene;

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
    final SelectedPassage? passage = _selectedPassage();

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
          if (widget.selectedAnchor != null && excerpt != null)
            WritingSelectedPassage(
              anchor: widget.selectedAnchor!,
              excerpt: excerpt,
              onClose: widget.onClearSelection ?? _closeNothing,
            ),
          if (passage != null)
            WritingSelectionBar(
              excerpt: passage.text,
              onComment: () => _comment(passage),
            ),
          Expanded(
            child: widget.isDocumentLoading
                ? const Center(child: LimpidSpinner())
                : LimpidSceneEditor(
                    key: ValueKey<String>(_editorKey()),
                    sceneId: current.id,
                    authorId: widget.authorId,
                    documentId: current.documentId,
                    controller: _manuscript.quill,
                    initialBlocks: widget.blocks,
                    readOnly: widget.isReadMode,
                    mode: widget.isReadMode
                        ? LimpidSceneEditorMode.readOnly
                        : LimpidSceneEditorMode.writing,
                    lamport: widget.lamport,
                    commentAnchors: widget.commentAnchors,
                    onSelectCommentRange: widget.onSelectAnchor,
                    onCursorMoved: _announceCursor,
                    remoteOperations: widget.remoteOperations,
                    dragHandleLabel: strings.hierarchyMoveBlock,
                    onChanged: widget.onChanged,
                  ),
          ),
        ],
      ),
    );
  }

  /// Annonce la position du curseur de l'auteur.
  ///
  /// Le décalage que l'éditeur donne est la position dans le document de
  /// l'éditeur ; les blocs de la scène savent où se trouve chaque
  /// paragraphe.
  void _announceCursor(int offset) {
    final void Function(String blockId, int offset)? callback =
        widget.onCursorMoved;
    if (callback == null) return;
    final (int index, int inside)? position = _positionOf(offset);
    if (position == null) return;
    final (int blockIndex, int blockOffset) = position;
    final List<SceneBlock> blocks = widget.blocks;
    if (blockIndex < 0 || blockIndex >= blocks.length) return;
    callback(blocks[blockIndex].id.value, blockOffset);
  }

  /// Le bloc qui porte le curseur à [offset], et le décalage dans ce bloc.
  ///
  /// L'éditeur pose les blocs les uns après les autres, chacun suivi de sa
  /// nouvelle ligne.
  (int, int)? _positionOf(int offset) {
    final List<SceneBlock> blocks = widget.blocks;
    if (blocks.isEmpty) return null;
    int start = 0;
    for (int index = 0; index < blocks.length; index++) {
      final int length = blocks[index].plainText.length;
      if (offset <= start + length) return (index, offset - start);
      start += length + 1;
    }
    final int last = blocks.length - 1;
    return (last, blocks[last].plainText.length);
  }

  /// Le texte couvert par l'ancre sélectionnée, dans le texte de la scène.
  String? _excerptOfSelectedAnchor() {
    final LimpidCommentAnchor? anchor = widget.selectedAnchor;
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

  /// Le texte de la scène, posé comme l'éditeur le pose.
  String _sceneTextOf() {
    final StringBuffer buffer = StringBuffer();
    for (final SceneBlock block in widget.blocks) {
      buffer.write(block.plainText);
      buffer.write('\n');
    }
    return buffer.toString();
  }
}
