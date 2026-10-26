import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta, Operation;
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'adapters/delta_block_adapter.dart';
import 'adapters/editor_remote_ops.dart';
import 'adapters/editor_sync_ops.dart';
import 'adapters/scene_block.dart';
import 'comment_anchors.dart';
import 'drag_handles.dart';
import 'editor_span_builder.dart';
import 'editor_theme.dart';
import 'slash_menu.dart';
import 'slash_menu_binding.dart';
import 'slash_menu_view.dart';

/// The working modes of the manuscript editor.
enum LimpidSceneEditorMode {
  /// The whole manuscript is visible and editable.
  writing,

  /// Only the paragraph being written stays fully opaque; the rest of the
  /// scene is dimmed (DESIGN_SYSTEM § 11.1).
  focus,

  /// The line being written stays vertically centred.
  typewriter,

  /// The manuscript is displayed but cannot be edited.
  readOnly,
}

/// The editor of one scene of the manuscript.
///
/// The editor renders the scene with the typography of the design system,
/// announces every change as a CRDT operation of `limpid_core` and offers
/// the slash menu, the drag handles and the comment anchors.
class LimpidSceneEditor extends StatefulWidget {
  /// Creates the editor of a scene.
  const LimpidSceneEditor({
    super.key,
    required this.sceneId,
    required this.authorId,
    this.documentId,
    this.initialContent,
    this.initialBlocks,
    this.readOnly = false,
    this.onChanged,
    this.focusNode,
    this.controller,
    this.mode = LimpidSceneEditorMode.writing,
    this.preset = LimpidEditorPreset.comfortable,
    this.placeholder,
    this.lamport = 0,
    this.commentAnchors = const <LimpidCommentAnchor>[],
    this.onSelectCommentRange,
    this.onCursorMoved,
    this.remoteOperations = const <SyncOp>[],
    this.onAiCommand,
    this.onInsertImage,
    this.slashMenuController,
    this.dragHandleLabel,
  });

  /// The identifier of the scene being edited.
  final SceneId sceneId;

  /// The author of the local edits; it stamps every emitted operation.
  final AuthorId authorId;

  /// The CRDT document holding the blocks of the scene.
  ///
  /// When it is `null`, the identifier is derived from [sceneId].
  final DocumentId? documentId;

  /// The content the editor starts with.
  final Delta? initialContent;

  /// The CRDT blocks backing the lines of the scene.
  ///
  /// When it is `null`, the editor mirrors [initialContent] into blocks
  /// whose identifiers are derived from the document identifier and the
  /// line index; supplying the blocks of the CRDT keeps the identifiers and
  /// the fractional indices of the application.
  ///
  /// An **empty** list means that the scene holds no block yet: the editor
  /// then writes the first one when the author types.
  final List<SceneBlock>? initialBlocks;

  /// Whether the scene cannot be edited.
  final bool readOnly;

  /// Called with the operations every local change produced.
  final ValueChanged<List<SyncOp>>? onChanged;

  /// The focus node of the editor.
  final FocusNode? focusNode;

  /// The controller of the editor; one is created when it is `null`.
  final QuillController? controller;

  /// The working mode of the editor.
  final LimpidSceneEditorMode mode;

  /// The typographic preset of the editor.
  final LimpidEditorPreset preset;

  /// The text shown when the scene is empty.
  final String? placeholder;

  /// The Lamport timestamp of the last operation produced by the editor.
  final int lamport;

  /// The comments anchored on the manuscript.
  final List<LimpidCommentAnchor> commentAnchors;

  /// Called when the author selects the range of a comment.
  final ValueChanged<LimpidCommentAnchor>? onSelectCommentRange;

  /// Called when the caret of the author moved.
  ///
  /// The offset is the position of the caret in the document of the editor:
  /// the caller maps it to the block it stands in. The presence of the relay
  /// uses it to announce where the author writes.
  final ValueChanged<int>? onCursorMoved;

  /// The operations another author produced.
  ///
  /// The editor applies them to its document: the text of the other author
  /// appears without the author losing the caret. They never leave the
  /// editor as local operations — they come from the relay, and they must
  /// not travel back to the server.
  final List<SyncOp> remoteOperations;

  /// Called when the author picks an AI command in the slash menu.
  final ValueChanged<LimpidSlashMenuItem>? onAiCommand;

  /// Called when the author asks for an image in the slash menu.
  final VoidCallback? onInsertImage;

  /// The controller of the slash menu; one is created when it is `null`.
  final LimpidSlashMenuController? slashMenuController;

  /// The label announced by the screen readers on the drag handles.
  ///
  /// When it is `null`, the handle keeps the label of the design system.
  final String? dragHandleLabel;

  @override
  State<LimpidSceneEditor> createState() => _LimpidSceneEditorState();
}

class _LimpidSceneEditorState extends State<LimpidSceneEditor> {
  late QuillController _controller;
  late bool _ownsController;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  late final GlobalKey<EditorState> _editorKey;
  late final ScrollController _scrollController;
  late final LimpidSlashMenuController _slashController;
  late final LimpidSlashMenuBinding _slashBinding;
  StreamSubscription<DocChange>? _subscription;
  SceneEditorState _state = SceneEditorState(
    document: Delta(),
    blocks: const <SceneBlock>[],
  );
  int _lamport = 0;
  int? _activeLineStart;
  int? _activeLineEnd;
  final Set<String> _appliedRemoteKeys = <String>{};

  DocumentId get _documentId =>
      widget.documentId ?? DocumentId(widget.sceneId.value);

  @override
  void initState() {
    super.initState();
    _editorKey = GlobalKey<EditorState>();
    _scrollController = ScrollController();
    _slashController =
        widget.slashMenuController ?? LimpidSlashMenuController();
    _slashBinding = LimpidSlashMenuBinding(
      controller: _controllerOrCreate(),
      menu: _slashController,
    );
    _slashController.onSelected = _onSlashItemSelected;
    _slashController.addListener(_onSlashMenuChanged);
    _lamport = widget.lamport;
    _ownsController = widget.controller == null;
    _controller = _slashBinding.controller;
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _controller.readOnly = _isReadOnly;
    _state = _buildState();
    _subscription = _controller.changes.listen(_onDocumentChanged);
    _controller.addListener(_onCursorMoved);
    _updateActiveLine();
  }

  @override
  void didUpdateWidget(LimpidSceneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscription?.cancel();
      _controller.removeListener(_onCursorMoved);
      _ownsController = widget.controller == null;
      _controller = _controllerOrCreate();
      _controller.readOnly = _isReadOnly;
      _state = _buildState();
      _subscription = _controller.changes.listen(_onDocumentChanged);
      _controller.addListener(_onCursorMoved);
      _updateActiveLine();
    }
    if (oldWidget.slashMenuController != widget.slashMenuController) {
      _slashController.onSelected = null;
    }
    if (!listEquals(oldWidget.remoteOperations, widget.remoteOperations)) {
      _applyRemoteOperations(widget.remoteOperations);
    }
    _controller.readOnly = _isReadOnly;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.removeListener(_onCursorMoved);
    _slashController.removeListener(_onSlashMenuChanged);
    _slashController.onSelected = null;
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isReadOnly =>
      widget.readOnly || widget.mode == LimpidSceneEditorMode.readOnly;

  bool get _isFocusMode => widget.mode == LimpidSceneEditorMode.focus;

  bool get _isTypewriterMode => widget.mode == LimpidSceneEditorMode.typewriter;

  QuillController _controllerOrCreate() {
    final QuillController? provided = widget.controller;
    if (provided != null) {
      return provided;
    }
    return QuillController(
      document: Document.fromDelta(_normalize(widget.initialContent)),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Delta _normalize(Delta? content) {
    if (content == null || content.isEmpty) {
      return Delta()..insert('\n');
    }
    final List<Operation> operations = content.toList();
    final Object? last = operations.last.data;
    if (last is String && last.endsWith('\n')) {
      return content;
    }
    return Delta.fromOperations(<Operation>[
      ...operations,
      Operation.insert('\n'),
    ]);
  }

  SceneEditorState _buildState() {
    final List<SceneBlock>? provided = widget.initialBlocks;
    if (provided != null) {
      if (provided.isEmpty) {
        // La scene est vide : l'editeur ne fabrique **aucun** bloc. Le
        // paragraphe vide de `flutter_quill` n'est qu'un remplacement
        // graphique — un bloc que le document CRDT ne connait pas ne peut
        // pas etre ecrit, et la premiere frappe du scripteur disparaitrait.
        return SceneEditorState(
          document: _controller.document.toDelta(),
          blocks: const <SceneBlock>[],
        );
      }
      return SceneEditorState(
        document: sceneBlocksToDelta(provided),
        blocks: List<SceneBlock>.unmodifiable(provided),
      );
    }
    final Delta document = _controller.document.toDelta();
    final List<SceneBlock> blocks = deltaToSceneBlocks(
      document,
      blockIdAt: (int index) => BlockId('${_documentId.value}-$index'),
      orderAt: (int index) => generateSceneOrders(index + 1).last,
    );
    return SceneEditorState(document: document, blocks: blocks);
  }

  void _onDocumentChanged(DocChange change) {
    final SceneChange conversion = convertLocalChange(
      doc: _documentId,
      author: widget.authorId,
      lamport: _lamport + 1,
      blocks: _state.blocks,
      before: change.before,
      change: change.change,
    );
    _lamport = conversion.lamport;
    _state = conversion.state;
    _updateActiveLine();
    _slashBinding.onDocumentChanged(change.change);
    widget.onChanged?.call(conversion.ops);
    if (_isTypewriterMode) {
      _scrollToCaret();
    }
  }

  void _onSlashMenuChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Announces the new position of the caret of the author.
  ///
  /// The editor listens to the controller: the caret moves without any
  /// change of the document, and the presence of the relay has to know it.
  void _onCursorMoved() {
    if (!mounted) return;
    widget.onCursorMoved?.call(_controller.selection.extentOffset);
  }

  /// Applies the operations another author produced.
  ///
  /// The document of the editor is rebuilt from the blocks the operations
  /// produced, and the caret of the author is put back where it was: the
  /// text of the other author appears without interrupting the writing.
  ///
  /// The operations never leave the editor as local operations: they come
  /// from the relay, and the server already knows them.
  ///
  /// The editor applies the operation as it arrives: a block the two
  /// authors edited at the same time keeps the version that came last. The
  /// CRDT arbitrates the divergence when the document is rebuilt from the
  /// journal.
  void _applyRemoteOperations(List<SyncOp> operations) {
    if (operations.isEmpty) return;
    final List<SyncOp> fresh = operations
        .where(
          (SyncOp operation) =>
              !_appliedRemoteKeys.contains(operation.operationKey),
        )
        .toList(growable: false);
    if (fresh.isEmpty) return;
    for (final SyncOp operation in fresh) {
      _appliedRemoteKeys.add(operation.operationKey);
    }

    SceneEditorState next = _state;
    for (final SyncOp operation in fresh) {
      next = applyRemoteOp(state: next, op: operation);
    }
    _state = next;

    final TextSelection selection = _controller.selection;
    _controller.document = Document.fromDelta(next.document);
    final int length = _controller.document.length;
    final int offset = length <= 0
        ? 0
        : selection.extentOffset.clamp(0, length - 1);
    _controller.updateSelection(
      TextSelection.collapsed(offset: offset),
      ChangeSource.local,
    );
    if (mounted) setState(() {});
  }

  void _updateActiveLine() {
    final (int, int)? range = editorLineRangeAt(
      _controller.document,
      _controller.selection.extentOffset,
    );
    if (range == null) {
      _activeLineStart = null;
      _activeLineEnd = null;
      return;
    }
    _activeLineStart = range.$1;
    _activeLineEnd = range.$2;
  }

  void _onSlashItemSelected(LimpidSlashMenuItem item) {
    _slashBinding.dismiss();
    if (item.kind == LimpidSlashMenuItemKind.ai) {
      widget.onAiCommand?.call(item);
      return;
    }
    final BlockType? type = item.blockType;
    if (type == null) {
      return;
    }
    if (type == BlockType.image) {
      widget.onInsertImage?.call();
      return;
    }
    _slashBinding.applyBlockType(type);
  }

  KeyEventResult? _onKeyPressed(KeyEvent event, Node? node) {
    if (_slashController.handleKeyEvent(event)) {
      return KeyEventResult.handled;
    }
    return null;
  }

  void _scrollToCaret() {
    if (!_scrollController.hasClients) {
      return;
    }
    final EditorState? editor = _editorKey.currentState;
    if (editor == null) {
      return;
    }
    final Rect caret = editor.renderEditor.getLocalRectForCaret(
      TextPosition(offset: _controller.selection.extentOffset),
    );
    final ScrollPosition position = _scrollController.position;
    final double target = caret.center.dy - position.viewportDimension / 2;
    final double clamped = target.clamp(0, position.maxScrollExtent);
    final bool animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate) {
      _scrollController.animateTo(
        clamped,
        duration: context.limpid.motion.base,
        curve: context.limpid.motion.standard,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  int get _activeLineIndex {
    final int? start = _activeLineStart;
    if (start == null) {
      return 0;
    }
    final String text = _controller.document.toPlainText();
    int count = 0;
    for (int i = 0; i < start && i < text.length; i++) {
      if (text[i] == '\n') {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidEditorTheme theme = LimpidEditorTheme.of(
      context,
      preset: widget.preset,
    );
    final LimpidEditorSpanBuilder spans = LimpidEditorSpanBuilder(
      colors: tokens.colors,
      isFocusMode: _isFocusMode,
      activeLineStart: _activeLineStart,
      activeLineEnd: _activeLineEnd,
      anchors: widget.commentAnchors,
      hoveredAnchorId: null,
    );

    return ColoredBox(
      color: tokens.colors.bgCanvas,
      child: Stack(
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: theme.measureWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!_isReadOnly) _dragHandles(),
                  Expanded(
                    child: QuillEditor(
                      key: _editorKey,
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        customStyles: theme.defaultStyles,
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spacing.space16,
                          vertical: tokens.spacing.space32,
                        ),
                        placeholder: widget.placeholder,
                        textSpanBuilder: spans.build,
                        // The key handler of `flutter_quill` is the documented
                        // hook for the keys pressed while the editor is focused;
                        // it is the only one that runs before the shortcuts of
                        // the editor, which would otherwise swallow the escape.
                        // ignore: experimental_member_use
                        onKeyPressed: _onKeyPressed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_slashController.isOpen)
            Positioned(
              left: 0,
              top: _activeLineIndex * theme.lineHeight,
              child: LimpidSlashMenu(controller: _slashController),
            ),
        ],
      ),
    );
  }

  /// The column of the handles that reorder the blocks of the scene.
  ///
  /// The handle is the one of `drag_handles.dart` : le deplacement qu'il
  /// produit ne porte que le nouvel index fractionnaire, le texte des blocs
  /// ne bouge jamais.
  Widget _dragHandles() {
    return LimpidDragHandles(
      blocks: <LimpidDraggableBlock>[
        for (final SceneBlock block in _state.blocks)
          LimpidDraggableBlock.fromSceneBlock(block),
      ],
      documentId: _documentId,
      authorId: widget.authorId,
      lamport: _lamport + 1,
      onMove: _onBlockMoved,
      handleBuilder: widget.dragHandleLabel == null
          ? null
          : (BuildContext context, LimpidDraggableBlock block) =>
                LimpidDragHandle(
                  semanticLabel: widget.dragHandleLabel!,
                  onDragStart: null,
                ),
    );
  }

  /// Announces the move of a block.
  ///
  /// L'operation est celle du CRDT : elle ne porte que la nouvelle place du
  /// bloc, et elle part par le meme chemin que les autres ecritures.
  void _onBlockMoved(MoveBlockOp operation) {
    _lamport = operation.lamport;
    widget.onChanged?.call(<SyncOp>[operation]);
  }
}
