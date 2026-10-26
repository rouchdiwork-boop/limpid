import 'package:limpid_core/limpid_core.dart';

import '../db/sync_op_record.dart';
import 'sync_protocol.dart';

/// A block of the reconstructed tree.
final class BlockNode {
  /// Creates a node.
  const BlockNode({
    required this.id,
    required this.parentId,
    required this.orderKey,
    required this.type,
    required this.content,
    required this.lamport,
    required this.authorId,
    required this.deleted,
    required this.version,
    required this.marks,
    required this.children,
  });

  /// The identifier of the block.
  final String id;

  /// The identifier of the parent block, `null` for a root block.
  final String? parentId;

  /// The fractional index of the block among its siblings.
  final String orderKey;

  /// The kind of the block.
  final String type;

  /// The plain text of the block.
  final String content;

  /// The Lamport timestamp of the last operation on the block.
  final int lamport;

  /// The author of the last operation on the block.
  final String authorId;

  /// Whether the block is a tombstone.
  final bool deleted;

  /// The version of the block.
  final int version;

  /// The marks of the block, indexed by mark identifier.
  final Map<String, Map<String, Object?>> marks;

  /// The children of the block, in reading order.
  final List<BlockNode> children;

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'parent_id': parentId,
      'order_key': orderKey,
      'type': type,
      'content': content,
      'lamport': lamport,
      'author_id': authorId,
      'deleted': deleted,
      'version': version,
      'marks': marks,
      'children': children.map((BlockNode child) => child.toJson()).toList(),
    };
  }
}

/// The reconstructed state of one synchronised document.
final class DocumentTree {
  /// Creates a tree.
  const DocumentTree({
    required this.docId,
    required this.lamport,
    required this.meta,
    required this.blocks,
    required this.operationCount,
  });

  /// The identifier of the document.
  final String docId;

  /// The highest Lamport timestamp known for the document.
  final int lamport;

  /// The effective metadata of the document.
  final Map<String, String> meta;

  /// The root blocks, in reading order.
  final List<BlockNode> blocks;

  /// The number of operations the tree was built from.
  final int operationCount;

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'doc_id': docId,
      'lamport': lamport,
      'meta': meta,
      'operation_count': operationCount,
      'blocks': blocks.map((BlockNode block) => block.toJson()).toList(),
    };
  }
}

/// Rebuilds the block trees of a project from its sync journal.
///
/// The reconstruction uses the CRDT engine of `limpid_core`: the tree is a
/// pure function of the set of operations, never of their order.
abstract final class TreeBuilder {
  /// Rebuilds the trees of every document of [operations].
  static List<DocumentTree> build(List<SyncOpRecord> operations) {
    final Map<String, List<SyncOpRecord>> byDocument =
        <String, List<SyncOpRecord>>{};
    for (final SyncOpRecord operation in operations) {
      byDocument
          .putIfAbsent(operation.docId, () => <SyncOpRecord>[])
          .add(operation);
    }

    final List<DocumentTree> trees = <DocumentTree>[];
    final List<String> docIds = byDocument.keys.toList(growable: false)..sort();
    for (final String docId in docIds) {
      trees.add(_buildDocument(docId, byDocument[docId]!));
    }
    return trees;
  }

  static DocumentTree _buildDocument(
    String docId,
    List<SyncOpRecord> operations,
  ) {
    CrdtDocument document = CrdtDocument.empty(DocumentId(docId));
    var lamport = 0;
    for (final SyncOpRecord operation in operations) {
      final SyncOp? decoded = _decode(operation);
      if (decoded == null) continue;
      document = document.apply(decoded);
      if (decoded.lamport > lamport) lamport = decoded.lamport;
    }

    final Map<String, BlockNode> nodes = <String, BlockNode>{};
    final Map<String, List<BlockNode>> children = <String, List<BlockNode>>{};

    for (final Block block in document.blocks) {
      final BlockNode node = BlockNode(
        id: block.id.value,
        parentId: block.parent?.value,
        orderKey: block.order.value,
        type: block.type.name,
        content: block.content.plainText,
        lamport: block.lamport,
        authorId: block.author.value,
        deleted: block.deleted,
        version: block.version,
        marks: _encodeMarks(block.marks),
        children: const <BlockNode>[],
      );
      nodes[node.id] = node;
      children.putIfAbsent(node.parentId ?? '', () => <BlockNode>[]).add(node);
    }

    final List<BlockNode> roots = <BlockNode>[];
    for (final BlockNode node in nodes.values) {
      if (node.parentId == null || !nodes.containsKey(node.parentId)) {
        roots.add(node);
      }
    }

    return DocumentTree(
      docId: docId,
      lamport: lamport,
      meta: document.meta,
      blocks: _attach(roots, children),
      operationCount: document.operationCount,
    );
  }

  static List<BlockNode> _attach(
    List<BlockNode> roots,
    Map<String, List<BlockNode>> children,
  ) {
    BlockNode resolve(BlockNode node) {
      final List<BlockNode> kids = children[node.id] ?? const <BlockNode>[];
      return BlockNode(
        id: node.id,
        parentId: node.parentId,
        orderKey: node.orderKey,
        type: node.type,
        content: node.content,
        lamport: node.lamport,
        authorId: node.authorId,
        deleted: node.deleted,
        version: node.version,
        marks: node.marks,
        children: kids.map(resolve).toList(growable: false),
      );
    }

    return roots.map(resolve).toList(growable: false);
  }

  static Map<String, Map<String, Object?>> _encodeMarks(
    Map<MarkId, MarkRange> marks,
  ) {
    final Map<String, Map<String, Object?>> encoded =
        <String, Map<String, Object?>>{};
    for (final MapEntry<MarkId, MarkRange> entry in marks.entries) {
      encoded[entry.key.value] = <String, Object?>{
        'start': entry.value.start,
        'end': entry.value.end,
      };
    }
    return encoded;
  }

  static SyncOp? _decode(SyncOpRecord operation) {
    try {
      return SyncProtocol.decodeRecord(operation);
    } on Object {
      // An operation that cannot be decoded is ignored by the projection: the
      // journal stays append-only and the client keeps its own state.
      return null;
    }
  }
}
