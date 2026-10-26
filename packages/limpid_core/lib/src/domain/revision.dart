import 'package:limpid_core/src/domain/block.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/internal/collections.dart';
import 'package:limpid_core/src/sync/block_state.dart';
import 'package:limpid_core/src/sync/crdt_document.dart';
import 'package:limpid_core/src/sync/internal/effective_state.dart';
import 'package:limpid_core/src/sync/ops.dart';

/// The revision of a document that precedes every other one.
///
/// It is the state of a document that holds no block: comparing a revision
/// with it shows every block the revision added.
final VersionRef originRevision = VersionRef(lamport: 0, author: AuthorId(''));

/// The kind of the change of a block between two revisions.
enum BlockChangeKind {
  /// The block did not exist in the first revision and exists in the second.
  added,

  /// The block existed in the first revision and does not exist any more.
  removed,

  /// The content of the block changed.
  modified,

  /// The block moved: its parent or its place among its siblings changed.
  moved,
}

/// The change of a block between two revisions.
///
/// The change carries the state of the block before and after, so that the
/// interface can show the difference itself: the text of a modified block,
/// the old and the new place of a moved one.
final class BlockChange {
  /// Creates a change.
  const BlockChange({
    required this.blockId,
    required this.kind,
    this.before,
    this.after,
    this.beforePosition,
    this.afterPosition,
  });

  /// The block that changed.
  final BlockId blockId;

  /// The kind of the change.
  final BlockChangeKind kind;

  /// The state of the block in the first revision, `null` when it was added.
  final Block? before;

  /// The state of the block in the second revision, `null` when it was
  /// removed.
  final Block? after;

  /// The place the block held in the first revision, counted from one.
  final int? beforePosition;

  /// The place the block holds in the second revision, counted from one.
  final int? afterPosition;

  /// The text the block held before the change.
  String get beforeText => before?.content.plainText ?? '';

  /// The text the block holds after the change.
  String get afterText => after?.content.plainText ?? '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockChange &&
          other.blockId == blockId &&
          other.kind == kind &&
          other.before == before &&
          other.after == after &&
          other.beforePosition == beforePosition &&
          other.afterPosition == afterPosition);

  @override
  int get hashCode =>
      Object.hash(blockId, kind, before, after, beforePosition, afterPosition);

  @override
  String toString() => 'BlockChange($blockId, $kind)';
}

/// A revision of a document.
///
/// The revision is a point of the history: the state of the document once
/// the operation that carries [ref] has been applied. The CRDT keeps the
/// forest of the versions of every block, and the revisions are the versions
/// it holds.
final class DocumentRevision {
  /// Creates a revision.
  const DocumentRevision({required this.ref, required this.blockCount});

  /// The operation that produced the revision.
  final VersionRef ref;

  /// The number of blocks the document held at the revision.
  final int blockCount;

  /// The author who produced the revision.
  AuthorId get author => ref.author;

  /// The Lamport timestamp of the revision.
  int get lamport => ref.lamport;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentRevision &&
          other.ref == ref &&
          other.blockCount == blockCount);

  @override
  int get hashCode => Object.hash(ref, blockCount);

  @override
  String toString() => 'DocumentRevision($ref, $blockCount blocks)';
}

/// The comparison of two revisions of a document.
///
/// The comparison is made **block by block**: it never compares two texts,
/// it compares the states of the blocks of the document.
final class RevisionComparison {
  /// Creates a comparison.
  const RevisionComparison({
    required this.from,
    required this.to,
    required this.changes,
  });

  /// Creates the empty comparison of two revisions.
  factory RevisionComparison.empty(VersionRef from, VersionRef to) =>
      RevisionComparison(from: from, to: to, changes: const <BlockChange>[]);

  /// The revision the comparison starts from.
  final VersionRef from;

  /// The revision the comparison ends at.
  final VersionRef to;

  /// The changes between the two revisions.
  final List<BlockChange> changes;

  /// The number of blocks that changed.
  int get changedBlockCount => changes.length;

  /// The number of blocks that were added.
  int get addedCount => _countOf(BlockChangeKind.added);

  /// The number of blocks that were removed.
  int get removedCount => _countOf(BlockChangeKind.removed);

  /// The number of blocks whose content changed.
  int get modifiedCount => _countOf(BlockChangeKind.modified);

  /// The number of blocks that moved.
  int get movedCount => _countOf(BlockChangeKind.moved);

  /// Whether the two revisions hold the same document.
  bool get isEmpty => changes.isEmpty;

  /// Counts the changes of [kind].
  int _countOf(BlockChangeKind kind) =>
      changes.where((BlockChange change) => change.kind == kind).length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionComparison &&
          other.from == from &&
          other.to == to &&
          listEquals(other.changes, changes));

  @override
  int get hashCode => Object.hash(from, to, Object.hashAll(changes));

  @override
  String toString() =>
      'RevisionComparison($from -> $to, ${changes.length} changes)';
}

/// The revisions of a document, the oldest first.
///
/// The revisions are the operations the document holds: every version of
/// every block, every insertion, every deletion and every move is a point of
/// the history. The document is read, never modified.
List<DocumentRevision> revisionsOf(CrdtDocument document) {
  final Map<String, VersionRef> refs = <String, VersionRef>{};
  for (final BlockState state in document.blockStates.values) {
    final InsertInfo? insert = state.insert;
    if (insert != null) {
      _remember(refs, insert.lamport, insert.author);
    }
    for (final ContentVersion version in state.versions) {
      _remember(refs, version.lamport, version.author);
    }
    final int? deletedAt = state.deletedAt;
    final AuthorId? deletedBy = state.deletedBy;
    if (deletedAt != null && deletedBy != null) {
      _remember(refs, deletedAt, deletedBy);
    }
    final MoveInfo? move = state.move;
    if (move != null) {
      _remember(refs, move.lamport, move.author);
    }
  }
  final List<VersionRef> ordered = refs.values.toList(growable: false)
    ..sort(_byVersion);
  return List<DocumentRevision>.unmodifiable(
    ordered.map((VersionRef ref) {
      return DocumentRevision(
        ref: ref,
        blockCount: _aliveBlocksAt(document, ref),
      );
    }),
  );
}

/// Compares two revisions of a document, block by block.
///
/// The comparison reports, for every block that changed, how it changed: it
/// was added, it was removed, its content changed or it moved. A block that
/// changed in several ways is reported once, with the strongest kind: an
/// addition, a removal, a modification, then a move.
RevisionComparison compareDocumentRevisions(
  CrdtDocument document, {
  required VersionRef from,
  required VersionRef to,
}) {
  final Map<BlockId, BlockState> states = document.blockStates;
  final Map<BlockId, Block> before = <BlockId, Block>{};
  final Map<BlockId, Block> after = <BlockId, Block>{};
  for (final BlockState state in states.values) {
    final Block? blockBefore = _blockAt(state, document.id, from);
    final Block? blockAfter = _blockAt(state, document.id, to);
    if (blockBefore != null) before[state.id] = blockBefore;
    if (blockAfter != null) after[state.id] = blockAfter;
  }
  final Map<BlockId, int> positionsBefore = _positionsOf(before);
  final Map<BlockId, int> positionsAfter = _positionsOf(after);
  final List<BlockChange> changes = <BlockChange>[];
  for (final Block block in document.blocks) {
    final BlockChange? change = _changeOf(
      block.id,
      before[block.id],
      after[block.id],
      positionsBefore[block.id],
      positionsAfter[block.id],
    );
    if (change != null) changes.add(change);
  }
  return RevisionComparison(
    from: from,
    to: to,
    changes: List<BlockChange>.unmodifiable(changes),
  );
}

/// The place of every block of [blocks] in the tree, counted from one.
Map<BlockId, int> _positionsOf(Map<BlockId, Block> blocks) {
  final List<Block> ordered = orderBlocks(
    blocks.values.toList(growable: false),
  );
  return <BlockId, int>{
    for (int index = 0; index < ordered.length; index++)
      ordered[index].id: index + 1,
  };
}

/// The change between two states of a block, `null` when nothing changed.
BlockChange? _changeOf(
  BlockId blockId,
  Block? before,
  Block? after,
  int? beforePosition,
  int? afterPosition,
) {
  if (before == null && after == null) return null;
  if (before == null) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.added,
      after: after,
      afterPosition: afterPosition,
    );
  }
  if (after == null) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.removed,
      before: before,
      beforePosition: beforePosition,
    );
  }
  if (before.deleted && !after.deleted) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.added,
      after: after,
      afterPosition: afterPosition,
    );
  }
  if (!before.deleted && after.deleted) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.removed,
      before: before,
      beforePosition: beforePosition,
    );
  }
  if (before.deleted && after.deleted) return null;
  if (_contentChanged(before, after)) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.modified,
      before: before,
      after: after,
      beforePosition: beforePosition,
      afterPosition: afterPosition,
    );
  }
  if (before.parent != after.parent || before.order != after.order) {
    return BlockChange(
      blockId: blockId,
      kind: BlockChangeKind.moved,
      before: before,
      after: after,
      beforePosition: beforePosition,
      afterPosition: afterPosition,
    );
  }
  return null;
}

/// Whether the content or the marks of the block changed.
bool _contentChanged(Block before, Block after) {
  if (before.content != after.content) return true;
  if (before.type != after.type) return true;
  return !mapEquals(before.marks, after.marks);
}

/// The state of a block at the revision [revision].
///
/// Returns `null` when the block did not exist yet.
Block? _blockAt(BlockState state, DocumentId documentId, VersionRef revision) {
  final InsertInfo? insert = state.insert;
  if (insert == null) return null;
  if (!_isAtOrBefore(insert.lamport, insert.author, revision)) return null;
  return effectiveBlock(_stateAt(state, revision), documentId);
}

/// The state of a block, cut at the revision [revision].
BlockState _stateAt(BlockState state, VersionRef revision) {
  final InsertInfo? insert = state.insert;
  final bool hasInsert =
      insert != null && _isAtOrBefore(insert.lamport, insert.author, revision);
  final int? deletedAt = state.deletedAt;
  final AuthorId? deletedBy = state.deletedBy;
  final bool isDeleted =
      deletedAt != null &&
      deletedBy != null &&
      _isAtOrBefore(deletedAt, deletedBy, revision);
  final MoveInfo? move = state.move;
  final bool hasMove =
      move != null && _isAtOrBefore(move.lamport, move.author, revision);
  final Map<MarkId, MarkState> marks = <MarkId, MarkState>{
    for (final MapEntry<MarkId, MarkState> entry in state.marks.entries)
      if (_isAtOrBefore(entry.value.addedAt, entry.value.addedBy, revision))
        entry.key: entry.value,
  };
  final Map<MarkId, int> removals = <MarkId, int>{
    for (final MapEntry<MarkId, int> entry in state.removals.entries)
      if (entry.value <= revision.lamport) entry.key: entry.value,
  };
  return BlockState(
    id: state.id,
    insert: hasInsert ? insert : null,
    versions: state.versions
        .where(
          (ContentVersion version) =>
              _isAtOrBefore(version.lamport, version.author, revision),
        )
        .toList(growable: false),
    deletedAt: isDeleted ? deletedAt : null,
    deletedBy: isDeleted ? deletedBy : null,
    move: hasMove ? move : null,
    marks: Map<MarkId, MarkState>.unmodifiable(marks),
    removals: Map<MarkId, int>.unmodifiable(removals),
    opCount: state.opCount,
  );
}

/// Whether the operation `(lamport, author)` is at or before the revision.
///
/// The revisions are ordered by their Lamport timestamp, and the author
/// breaks the ties, exactly like the versions of a block.
bool _isAtOrBefore(int lamport, AuthorId author, VersionRef revision) {
  if (lamport != revision.lamport) return lamport < revision.lamport;
  return author.value.compareTo(revision.author.value) <= 0;
}

/// The number of blocks the document held at the revision [revision].
int _aliveBlocksAt(CrdtDocument document, VersionRef revision) {
  var count = 0;
  for (final BlockState state in document.blockStates.values) {
    final Block? block = _blockAt(state, document.id, revision);
    if (block != null && !block.deleted) count++;
  }
  return count;
}

/// Remembers the revision `(lamport, author)` in [refs].
void _remember(Map<String, VersionRef> refs, int lamport, AuthorId author) {
  final VersionRef ref = VersionRef(lamport: lamport, author: author);
  refs[ref.key] = ref;
}

/// Orders two revisions, the oldest first.
int _byVersion(VersionRef a, VersionRef b) {
  final int byLamport = a.lamport.compareTo(b.lamport);
  if (byLamport != 0) return byLamport;
  return a.author.value.compareTo(b.author.value);
}
