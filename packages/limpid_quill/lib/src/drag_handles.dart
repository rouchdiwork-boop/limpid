import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'adapters/scene_block.dart';

/// The size of a drag handle, in logical pixels (DESIGN_SYSTEM § 11.1).
const double kDragHandleSize = 24;

/// A block that can be dragged inside the editor.
@immutable
class LimpidDraggableBlock {
  /// Creates a draggable block.
  const LimpidDraggableBlock({
    required this.id,
    required this.order,
    this.parent,
  });

  /// Builds the description of a scene block.
  factory LimpidDraggableBlock.fromSceneBlock(SceneBlock block) {
    return LimpidDraggableBlock(
      id: block.id,
      order: block.order,
      parent: block.parent,
    );
  }

  /// The identifier of the block.
  final BlockId id;

  /// The fractional index of the block among its siblings.
  final OrderKey order;

  /// The parent of the block, `null` for a root block.
  final BlockId? parent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimpidDraggableBlock &&
          other.id == id &&
          other.order == order &&
          other.parent == parent);

  @override
  int get hashCode => Object.hash(id, order, parent);
}

/// Computes the move operation reordering [blockId] at [targetIndex].
///
/// The new position is expressed as a fractional index strictly between the
/// order keys of the new neighbours: an integer index is never used and an
/// existing key is never rewritten, which is what makes concurrent moves
/// converge (D-04).
///
/// Throws an [ArgumentError] when [blockId] is not part of [blocks].
MoveBlockOp computeBlockMove({
  required DocumentId doc,
  required AuthorId author,
  required int lamport,
  required List<LimpidDraggableBlock> blocks,
  required BlockId blockId,
  required int targetIndex,
}) {
  final LimpidDraggableBlock? moving = _findBlock(blocks, blockId);
  if (moving == null) {
    throw ArgumentError.value(blockId, 'blockId', 'Unknown block');
  }
  final List<LimpidDraggableBlock> remaining = blocks
      .where((LimpidDraggableBlock block) => block.id != blockId)
      .toList(growable: false);
  final int index = targetIndex.clamp(0, remaining.length);
  final OrderKey? lower = index == 0 ? null : remaining[index - 1].order;
  final OrderKey? upper = index == remaining.length
      ? null
      : remaining[index].order;
  return MoveBlockOp(
    doc: doc,
    lamport: lamport,
    author: author,
    blockId: blockId,
    parent: moving.parent,
    order: _orderBetween(lower, upper),
  );
}

OrderKey _orderBetween(OrderKey? lower, OrderKey? upper) {
  if (lower == null && upper == null) {
    return OrderKey.initial;
  }
  if (lower == null) {
    return OrderKey.between(null, upper);
  }
  if (upper == null) {
    return OrderKey.between(lower, null);
  }
  if (lower.compareTo(upper) >= 0) {
    return OrderKey.between(lower, null);
  }
  return OrderKey.between(lower, upper);
}

/// The handle that drags a block from one place to another.
///
/// The handle appears on hover, measures 24 × 24 logical pixels and wears
/// the raised surface of the theme (DESIGN_SYSTEM § 11.1).
class LimpidDragHandle extends StatefulWidget {
  /// Creates a drag handle.
  const LimpidDragHandle({
    super.key,
    required this.onDragStart,
    this.semanticLabel = 'Déplacer le bloc',
    this.isEnabled = true,
  });

  /// Called when the user starts dragging the block.
  final VoidCallback? onDragStart;

  /// The label announced by the screen readers.
  final String semanticLabel;

  /// Whether the handle reacts to the pointer.
  final bool isEnabled;

  @override
  State<LimpidDragHandle> createState() => _LimpidDragHandleState();
}

class _LimpidDragHandleState extends State<LimpidDragHandle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final bool animate =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _isHovered = true),
      onExit: (PointerExitEvent _) => setState(() => _isHovered = false),
      child: Semantics(
        button: true,
        enabled: widget.isEnabled,
        label: widget.semanticLabel,
        child: AnimatedOpacity(
          opacity: _isHovered || !widget.isEnabled ? 1 : 0,
          duration: animate ? tokens.motion.fast : Duration.zero,
          curve: tokens.motion.standard,
          child: SizedBox(
            width: kDragHandleSize,
            height: kDragHandleSize,
            child: Material(
              color: tokens.colors.bgRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radii.xs),
                side: BorderSide(color: tokens.colors.borderDefault),
              ),
              child: InkWell(
                onTap: widget.onDragStart,
                borderRadius: BorderRadius.circular(tokens.radii.xs),
                child: Icon(
                  LimpidIcons.dragHandle,
                  size: 16,
                  color: tokens.colors.fgMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The column of drag handles of a scene.
///
/// Dropping a handle on another one reorders the blocks: the move is
/// expressed with a fractional index computed by [computeBlockMove].
class LimpidDragHandles extends StatelessWidget {
  /// Creates the column of drag handles.
  const LimpidDragHandles({
    super.key,
    required this.blocks,
    required this.documentId,
    required this.authorId,
    required this.lamport,
    required this.onMove,
    this.handleBuilder,
  });

  /// The blocks that can be dragged, in the order they appear.
  final List<LimpidDraggableBlock> blocks;

  /// The CRDT document the blocks belong to.
  final DocumentId documentId;

  /// The author of the move.
  final AuthorId authorId;

  /// The Lamport timestamp of the move.
  final int lamport;

  /// Called with the move operation produced by a drop.
  final ValueChanged<MoveBlockOp> onMove;

  /// Builds the handle of a block; defaults to a [LimpidDragHandle].
  final Widget Function(BuildContext context, LimpidDraggableBlock block)?
  handleBuilder;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < blocks.length; index++)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacing.space8),
            child: DragTarget<LimpidDraggableBlock>(
              onWillAcceptWithDetails:
                  (DragTargetDetails<LimpidDraggableBlock> details) =>
                      details.data.id != blocks[index].id,
              onAcceptWithDetails:
                  (DragTargetDetails<LimpidDraggableBlock> details) {
                    onMove(
                      computeBlockMove(
                        doc: documentId,
                        author: authorId,
                        lamport: lamport,
                        blocks: blocks,
                        blockId: details.data.id,
                        targetIndex: index,
                      ),
                    );
                  },
              builder:
                  (
                    BuildContext context,
                    List<LimpidDraggableBlock?> candidates,
                    List<Object?> rejected,
                  ) {
                    return Draggable<LimpidDraggableBlock>(
                      data: blocks[index],
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _DragFeedback(block: blocks[index]),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: _handle(context, blocks[index]),
                      ),
                      child: _handle(context, blocks[index]),
                    );
                  },
            ),
          ),
      ],
    );
  }

  Widget _handle(BuildContext context, LimpidDraggableBlock block) {
    final builder = handleBuilder;
    if (builder != null) {
      return builder(context, block);
    }
    return LimpidDragHandle(onDragStart: null);
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.block});

  final LimpidDraggableBlock block;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    return Container(
      width: kDragHandleSize,
      height: kDragHandleSize,
      decoration: BoxDecoration(
        color: tokens.colors.bgRaised,
        borderRadius: BorderRadius.circular(tokens.radii.xs),
        border: Border.all(color: tokens.colors.borderStrong),
      ),
      child: Icon(
        LimpidIcons.dragHandle,
        size: 16,
        color: tokens.colors.fgMuted,
      ),
    );
  }
}

/// Returns the block carrying [id], or `null`.
LimpidDraggableBlock? _findBlock(
  List<LimpidDraggableBlock> blocks,
  BlockId id,
) {
  for (final LimpidDraggableBlock block in blocks) {
    if (block.id == id) {
      return block;
    }
  }
  return null;
}
