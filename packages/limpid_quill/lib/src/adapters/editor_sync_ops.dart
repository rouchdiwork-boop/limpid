import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:limpid_core/limpid_core.dart';

import 'delta_block_adapter.dart';
import 'editor_line_alignment.dart';
import 'scene_block.dart';

/// The outcome of a local editor change.
@immutable
class SceneChange {
  /// Creates the outcome of a change.
  const SceneChange({
    required this.ops,
    required this.state,
    required this.lamport,
  });

  /// The operations the change produced.
  final List<SyncOp> ops;

  /// The state of the scene after the change.
  final SceneEditorState state;

  /// The Lamport timestamp stamped on the operations.
  final int lamport;
}

/// Converts a local editor change into the CRDT operations it represents
/// and the new state of the scene.
///
/// The change delta is walked operation by operation: a text insertion or a
/// deletion inside a line updates the block of that line, an inserted
/// newline creates a block and a deleted newline merges two lines — the
/// merged block is then deleted.
///
/// The kind of a block is not part of [UpdateContentOp]: when it changes,
/// the block is replaced by a new one, because the CRDT vocabulary of
/// `limpid_core` knows no "set type" operation.
SceneChange convertLocalChange({
  required DocumentId doc,
  required AuthorId author,
  required int lamport,
  required List<SceneBlock> blocks,
  required Delta before,
  required Delta change,
  BlockId Function()? blockIdFactory,
}) {
  if (change.isEmpty) {
    return SceneChange(
      ops: const <SyncOp>[],
      state: SceneEditorState(document: before, blocks: blocks),
      lamport: lamport,
    );
  }
  final BlockId Function() newBlockId =
      blockIdFactory ?? _defaultBlockIdFactory();

  final Delta after = before.compose(change);
  final List<LimpidEditorLine> afterLines = splitEditorLines(after);
  final List<int> origins = alignEditorLines(
    flattenEditorLines(before),
    change,
    afterLines.length,
  );

  final List<_PendingBlock> pending = <_PendingBlock>[];
  for (int j = 0; j < afterLines.length; j++) {
    final int origin = j < origins.length ? origins[j] : kNewLineOrigin;
    final LimpidEditorLine line = afterLines[j];
    final BlockContent content = deltaToBlockContent(line.content);
    if (origin >= 0 && origin < blocks.length) {
      final SceneBlock original = blocks[origin];
      final bool keepsType = original.type == line.type;
      pending.add(
        _PendingBlock(
          originId: original.id,
          id: keepsType ? original.id : newBlockId(),
          type: line.type,
          content: content,
          order: original.order,
          parent: original.parent,
        ),
      );
      continue;
    }
    pending.add(
      _PendingBlock(
        originId: null,
        id: newBlockId(),
        type: line.type,
        content: content,
        order: OrderKey.initial,
        parent: null,
      ),
    );
  }
  _placeNewBlocks(pending);

  final List<SyncOp> ops = <SyncOp>[];
  for (final SceneBlock block in blocks) {
    final _PendingBlock? match = _matchOrigin(pending, block.id);
    if (match == null) {
      ops.add(
        DeleteBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: block.id,
        ),
      );
      continue;
    }
    if (match.id != block.id) {
      ops.add(
        DeleteBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: block.id,
        ),
      );
      ops.add(
        InsertBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: match.id,
          parent: match.parent,
          order: match.order,
          type: match.type,
          content: match.content,
        ),
      );
      continue;
    }
    if (match.content != block.content) {
      ops.add(
        UpdateContentOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: block.id,
          content: match.content,
        ),
      );
    }
  }
  for (final _PendingBlock block in pending) {
    if (block.originId != null) {
      continue;
    }
    ops.add(
      InsertBlockOp(
        doc: doc,
        lamport: lamport,
        author: author,
        blockId: block.id,
        parent: block.parent,
        order: block.order,
        type: block.type,
        content: block.content,
      ),
    );
  }

  final List<SceneBlock> newBlocks = pending
      .map(
        (_PendingBlock block) => SceneBlock(
          id: block.id,
          type: block.type,
          content: block.content,
          order: block.order,
          parent: block.parent,
        ),
      )
      .toList(growable: false);

  return SceneChange(
    ops: ops,
    state: SceneEditorState(document: after, blocks: newBlocks),
    lamport: lamport,
  );
}

/// Converts a local editor change into the CRDT operations it represents.
List<SyncOp> changeToSyncOps({
  required DocumentId doc,
  required AuthorId author,
  required int lamport,
  required List<SceneBlock> blocks,
  required Delta before,
  required Delta change,
  BlockId Function()? blockIdFactory,
}) {
  return convertLocalChange(
    doc: doc,
    author: author,
    lamport: lamport,
    blocks: blocks,
    before: before,
    change: change,
    blockIdFactory: blockIdFactory,
  ).ops;
}

/// A block produced by a change, before it becomes a [SceneBlock].
@immutable
class _PendingBlock {
  const _PendingBlock({
    required this.originId,
    required this.id,
    required this.type,
    required this.content,
    required this.order,
    required this.parent,
  });

  /// The identifier of the block this one comes from, `null` when the
  /// change created it.
  final BlockId? originId;

  /// The identifier of the block.
  final BlockId id;

  /// The kind of the block.
  final BlockType type;

  /// The content of the block.
  final BlockContent content;

  /// The fractional index of the block.
  final OrderKey order;

  /// The parent of the block.
  final BlockId? parent;

  /// Returns a copy of this block with the given fields replaced.
  _PendingBlock copyWith({OrderKey? order, BlockId? parent}) => _PendingBlock(
    originId: originId,
    id: id,
    type: type,
    content: content,
    order: order ?? this.order,
    parent: parent ?? this.parent,
  );
}

/// Places the blocks created by a change between their new neighbours.
///
/// The fractional index is computed with [OrderKey.between], never with an
/// integer index: the key of an existing block is never rewritten.
void _placeNewBlocks(List<_PendingBlock> pending) {
  for (int j = 0; j < pending.length; j++) {
    if (pending[j].originId != null) {
      continue;
    }
    final _PendingBlock? previous = _neighbour(pending, j, isPrevious: true);
    final _PendingBlock? next = _neighbour(pending, j, isPrevious: false);
    pending[j] = pending[j].copyWith(
      order: _orderBetween(previous?.order, next?.order),
      parent: previous?.parent ?? next?.parent,
    );
  }
}

_PendingBlock? _neighbour(
  List<_PendingBlock> pending,
  int index, {
  required bool isPrevious,
}) {
  if (isPrevious) {
    for (int j = index - 1; j >= 0; j--) {
      if (pending[j].originId != null) {
        return pending[j];
      }
    }
    return null;
  }
  for (int j = index + 1; j < pending.length; j++) {
    if (pending[j].originId != null) {
      return pending[j];
    }
  }
  return null;
}

_PendingBlock? _matchOrigin(List<_PendingBlock> pending, BlockId id) {
  for (final _PendingBlock block in pending) {
    if (block.originId == id) {
      return block;
    }
  }
  return null;
}

OrderKey _orderBetween(OrderKey? previous, OrderKey? next) {
  if (previous == null && next == null) {
    return OrderKey.initial;
  }
  if (previous == null) {
    return OrderKey.between(null, next);
  }
  if (next == null) {
    return OrderKey.between(previous, null);
  }
  if (previous.compareTo(next) >= 0) {
    return OrderKey.between(previous, null);
  }
  return OrderKey.between(previous, next);
}

BlockId Function() _defaultBlockIdFactory() {
  final UlidGenerator generator = UlidGenerator();
  return () => BlockId(generator.generate().value);
}
