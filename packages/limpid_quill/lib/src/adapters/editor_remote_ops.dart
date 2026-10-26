import 'package:limpid_core/limpid_core.dart';

import 'delta_block_adapter.dart';
import 'scene_block.dart';

/// Applies a remote CRDT operation to an editor document.
///
/// The operation is applied to the block list, then the editor document is
/// rebuilt from it: the editor and the CRDT never drift apart.
///
/// The metadata and mark operations are ignored: they do not change the
/// text of the manuscript.
SceneEditorState applyRemoteOp({
  required SceneEditorState state,
  required SyncOp op,
}) {
  switch (op) {
    case UpdateContentOp(:final BlockId blockId, :final BlockContent content):
      final List<SceneBlock> blocks = state.blocks
          .map(
            (SceneBlock block) =>
                block.id == blockId ? block.copyWith(content: content) : block,
          )
          .toList(growable: false);
      return SceneEditorState(
        document: sceneBlocksToDelta(blocks),
        blocks: blocks,
      );
    case DeleteBlockOp(:final BlockId blockId):
      final List<SceneBlock> blocks = state.blocks
          .where((SceneBlock block) => block.id != blockId)
          .toList(growable: false);
      return SceneEditorState(
        document: sceneBlocksToDelta(blocks),
        blocks: blocks,
      );
    case InsertBlockOp(
      :final BlockId blockId,
      :final BlockId? parent,
      :final OrderKey order,
      :final BlockType type,
      :final BlockContent content,
    ):
      final List<SceneBlock> blocks = List<SceneBlock>.of(state.blocks);
      final SceneBlock inserted = SceneBlock(
        id: blockId,
        type: type,
        content: content,
        order: order,
        parent: parent,
      );
      blocks.insert(_insertionIndex(blocks, order, parent), inserted);
      return SceneEditorState(
        document: sceneBlocksToDelta(blocks),
        blocks: blocks,
      );
    case MoveBlockOp(:final BlockId blockId, :final OrderKey order):
      final List<SceneBlock> blocks = state.blocks
          .where((SceneBlock block) => block.id != blockId)
          .toList();
      final SceneBlock moved = state.blocks.firstWhere(
        (SceneBlock block) => block.id == blockId,
      );
      blocks.insert(
        _insertionIndex(blocks, order, null),
        moved.copyWith(order: order),
      );
      return SceneEditorState(
        document: sceneBlocksToDelta(blocks),
        blocks: blocks,
      );
    case SetMetaOp() || AddMarkOp() || RemoveMarkOp():
      return state;
  }
}

/// Returns the index at which a block carrying [order] must be inserted.
int _insertionIndex(List<SceneBlock> blocks, OrderKey order, BlockId? parent) {
  int index = 0;
  while (index < blocks.length) {
    final SceneBlock block = blocks[index];
    if (block.parent != parent) {
      index++;
      continue;
    }
    if (block.order.compareTo(order) >= 0) {
      break;
    }
    index++;
  }
  return index;
}
