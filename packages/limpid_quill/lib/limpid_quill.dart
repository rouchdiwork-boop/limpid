/// The manuscript editor of Limpid.
///
/// The package provides the scene editor — a `flutter_quill` editor enriched
/// with the slash menu, the drag handles, the inline AI actions and the
/// comment anchors — and the adapter that bridges the Delta model of the
/// editor to the CRDT model of `limpid_core`.
///
/// ```dart
/// LimpidSceneEditor(
///   sceneId: scene.id,
///   authorId: authorId,
///   documentId: scene.documentId,
///   initialContent: delta,
///   onChanged: (List<SyncOp> ops) => sync.push(ops),
/// );
/// ```
library;

export 'package:limpid_core/limpid_core.dart'
    show
        AddMarkOp,
        AuthorId,
        Block,
        BlockContent,
        BlockId,
        BlockType,
        ContentBase,
        DeleteBlockOp,
        DocumentId,
        InlineContent,
        InsertBlockOp,
        LamportClock,
        MarkId,
        MarkRange,
        MarkType,
        MoveBlockOp,
        OrderKey,
        RemoveMarkOp,
        SceneId,
        SetMetaOp,
        SyncOp,
        TextContent,
        UpdateContentOp;

export 'src/accessibility.dart';
export 'src/adapters/delta_block_adapter.dart';
export 'src/adapters/editor_line_alignment.dart';
export 'src/adapters/editor_remote_ops.dart';
export 'src/adapters/editor_sync_ops.dart';
export 'src/adapters/scene_block.dart';
export 'src/comment_anchors.dart';
export 'src/drag_handles.dart';
export 'src/editor_span_builder.dart';
export 'src/editor_theme.dart';
export 'src/inline_ai_actions.dart';
export 'src/scene_editor.dart';
export 'src/slash_menu.dart';
export 'src/slash_menu_binding.dart';
export 'src/slash_menu_view.dart';
export 'src/word_diff.dart';
