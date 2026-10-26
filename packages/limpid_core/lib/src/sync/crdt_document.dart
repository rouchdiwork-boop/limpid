import 'package:limpid_core/src/domain/block.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/errors.dart';
import 'package:limpid_core/src/sync/block_state.dart';
import 'package:limpid_core/src/sync/internal/effective_state.dart';
import 'package:limpid_core/src/sync/ops.dart';

/// The CRDT state of a document.
///
/// The state is a pure function of the *set* of operations it has seen: the
/// effective blocks and metadata only depend on which operations were
/// applied, never on the order in which they arrived. Two replicas holding
/// the same operations therefore always compute the same state.
///
/// [CrdtDocument] is immutable: [apply] returns a new document.
final class CrdtDocument {
  const CrdtDocument._(this.id, this._blocks, this._meta, this._applied);

  /// Creates an empty document.
  factory CrdtDocument.empty(DocumentId id) => CrdtDocument._(
    id,
    const <BlockId, BlockState>{},
    const <String, MetaEntry>{},
    const <String>{},
  );

  /// The identifier of the document.
  final DocumentId id;

  final Map<BlockId, BlockState> _blocks;
  final Map<String, MetaEntry> _meta;
  final Set<String> _applied;

  /// The number of operations already applied.
  int get operationCount => _applied.length;

  /// Whether the operation was already applied.
  bool hasApplied(SyncOp op) => _applied.contains(op.operationKey);

  /// The most recent known content version of [blockId].
  ///
  /// It is used as the common ancestor of the next local edit of the block.
  /// Returns `null` when the block is unknown.
  VersionRef? latestContentVersion(BlockId blockId) {
    final state = _blocks[blockId];
    if (state == null) return null;
    return latestContentVersionOf(state);
  }

  /// The effective metadata of the document.
  Map<String, String> get meta => Map<String, String>.unmodifiable(
    _meta.map((key, entry) => MapEntry(key, entry.value)),
  );

  /// The effective blocks of the document, in tree order.
  ///
  /// Deleted blocks are part of the returned list with their `deleted` flag
  /// set: the tombstone is part of the state and must be propagated.
  List<Block> get blocks {
    final effective = <Block>[];
    for (final state in _blocks.values) {
      final block = effectiveBlock(state, id);
      if (block != null) effective.add(block);
    }
    return List<Block>.unmodifiable(orderBlocks(effective));
  }

  /// Applies [op] and returns the resulting document.
  ///
  /// Applying the same operation twice returns the same document: operations
  /// are idempotent by `(doc, lamport, author)`.
  ///
  /// Throws an [InvalidSyncOperationException] when the operation targets
  /// another document.
  CrdtDocument apply(SyncOp op) {
    if (op.doc != id) {
      throw InvalidSyncOperationException(
        'Operation ${op.operationKey} targets document ${op.doc.value}, '
        'not ${id.value}.',
      );
    }
    if (_applied.contains(op.operationKey)) return this;
    return switch (op) {
      InsertBlockOp() => _applyInsert(op),
      DeleteBlockOp() => _applyDelete(op),
      UpdateContentOp() => _applyUpdate(op),
      MoveBlockOp() => _applyMove(op),
      SetMetaOp() => _applySetMeta(op),
      AddMarkOp() => _applyAddMark(op),
      RemoveMarkOp() => _applyRemoveMark(op),
    };
  }

  /// Applies every operation of [ops] and returns the resulting document.
  CrdtDocument applyAll(Iterable<SyncOp> ops) {
    var document = this;
    for (final op in ops) {
      document = document.apply(op);
    }
    return document;
  }

  CrdtDocument _withBlocks(
    Map<BlockId, BlockState> blocks,
    Map<String, MetaEntry> meta,
    String appliedKey,
  ) {
    return CrdtDocument._(
      id,
      Map<BlockId, BlockState>.unmodifiable(blocks),
      Map<String, MetaEntry>.unmodifiable(meta),
      Set<String>.unmodifiable(<String>{..._applied, appliedKey}),
    );
  }

  CrdtDocument _applyInsert(InsertBlockOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final insert = InsertInfo(
      lamport: op.lamport,
      author: op.author,
      parent: op.parent,
      order: op.order,
      type: op.type,
      content: op.content,
    );
    final current = state.insert;
    final keepsCurrent =
        current != null && !isNewerVersion(op.lamport, op.author, current.key);
    final versions = [
      ...state.versions,
      ContentVersion(
        lamport: op.lamport,
        author: op.author,
        content: op.content,
      ),
    ];
    blocks[op.blockId] = state.copyWith(
      insert: keepsCurrent ? current : insert,
      versions: versions,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }

  CrdtDocument _applyDelete(DeleteBlockOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final current = state.deletedAt;
    final currentAuthor = state.deletedBy;
    final isNewer =
        current == null ||
        op.lamport > current ||
        (op.lamport == current &&
            currentAuthor != null &&
            op.author.value.compareTo(currentAuthor.value) > 0);
    blocks[op.blockId] = state.copyWith(
      deletedAt: isNewer ? op.lamport : current,
      deletedBy: isNewer ? op.author : currentAuthor,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }

  CrdtDocument _applyUpdate(UpdateContentOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final versions = [
      ...state.versions,
      ContentVersion(
        lamport: op.lamport,
        author: op.author,
        content: op.content,
        base: op.base?.version,
      ),
    ];
    blocks[op.blockId] = state.copyWith(
      versions: versions,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }

  CrdtDocument _applyMove(MoveBlockOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final current = state.move;
    final keepsCurrent =
        current != null && !isNewerVersion(op.lamport, op.author, current.key);
    final move = MoveInfo(
      lamport: op.lamport,
      author: op.author,
      parent: op.parent,
      order: op.order,
    );
    blocks[op.blockId] = state.copyWith(
      move: keepsCurrent ? current : move,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }

  CrdtDocument _applySetMeta(SetMetaOp op) {
    final meta = Map<String, MetaEntry>.of(_meta);
    final current = meta[op.key];
    final keepsCurrent =
        current != null && !isNewerVersion(op.lamport, op.author, current.key);
    if (!keepsCurrent) {
      meta[op.key] = MetaEntry(
        lamport: op.lamport,
        author: op.author,
        value: op.value,
      );
    }
    return _withBlocks(_blocks, meta, op.operationKey);
  }

  CrdtDocument _applyAddMark(AddMarkOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final marks = Map<MarkId, MarkState>.of(state.marks);
    final current = marks[op.markId];
    final isNewer =
        current == null ||
        isNewerVersion(
          op.lamport,
          op.author,
          '${current.addedAt}/${current.addedBy.value}',
        );
    if (isNewer) {
      marks[op.markId] = MarkState(
        addedAt: op.lamport,
        addedBy: op.author,
        type: op.type,
        range: op.range,
        body: op.body,
      );
    }
    blocks[op.blockId] = state.copyWith(
      marks: marks,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }

  CrdtDocument _applyRemoveMark(RemoveMarkOp op) {
    final blocks = Map<BlockId, BlockState>.of(_blocks);
    final state = blocks[op.blockId] ?? BlockState(id: op.blockId);
    final removals = Map<MarkId, int>.of(state.removals);
    final current = removals[op.markId];
    if (current == null || op.lamport > current) {
      removals[op.markId] = op.lamport;
    }
    blocks[op.blockId] = state.copyWith(
      removals: removals,
      opCount: state.opCount + 1,
    );
    return _withBlocks(blocks, _meta, op.operationKey);
  }
}
