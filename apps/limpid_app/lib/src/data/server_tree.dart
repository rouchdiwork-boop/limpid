import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// The tree of a document, as the server rebuilt it.
///
/// ## What the tree carries
///
/// The server rebuilds the documents of a project from its journal: the tree
/// is the state the server holds, block by block — the identifier, the
/// parent, the order, the type, the plain text, the tombstone and the range
/// of the marks.
///
/// ## What the tree loses
///
/// The route carries the **plain text** of the blocks, not their rich
/// content, and the **range** of the marks, not their nature. The client
/// rebuilds the blocks it can: the text and the structure of the manuscript
/// are exact, the rich content and the nature of the marks are lost.
final class ServerDocumentTree {
  /// Creates a tree.
  const ServerDocumentTree({
    required this.documentId,
    required this.lamport,
    required this.meta,
    required this.blocks,
    required this.operationCount,
  });

  /// Reads the tree from the answer of the API.
  ///
  /// The blocks of the tree are nested: the roots carry their children. The
  /// tree is flattened, because the parent of every block is named.
  factory ServerDocumentTree.fromJson(Map<String, Object?> json) {
    final List<ServerBlock> blocks = <ServerBlock>[];
    _collect(json['blocks'], blocks);
    return ServerDocumentTree(
      documentId: _text(json, 'doc_id'),
      lamport: _integer(json, 'lamport'),
      meta: _meta(json['meta']),
      blocks: List<ServerBlock>.unmodifiable(blocks),
      operationCount: _integer(json, 'operation_count'),
    );
  }

  /// The identifier of the document.
  final String documentId;

  /// The highest Lamport timestamp the server knows for the document.
  final int lamport;

  /// The metadata of the document.
  final Map<String, String> meta;

  /// The blocks of the document, in reading order.
  final List<ServerBlock> blocks;

  /// The number of operations the server built the tree from.
  final int operationCount;

  /// The state of the document, as the client stores it.
  ///
  /// The state replaces the journal of the document: the client restores
  /// the document from it, and the operations the server has not accepted
  /// yet are replayed on top of it.
  CrdtState toState() {
    return CrdtState(
      documentId: DocumentId(documentId),
      blocks: Map<BlockId, BlockState>.unmodifiable(<BlockId, BlockState>{
        for (final ServerBlock block in blocks)
          BlockId(block.id): block.toState(),
      }),
      meta: Map<String, MetaEntry>.unmodifiable(<String, MetaEntry>{
        for (final MapEntry<String, String> entry in meta.entries)
          entry.key: MetaEntry(
            lamport: lamport,
            // The tree does not name the author of a metadata: the write is
            // dated, not signed.
            author: const AuthorId(''),
            value: entry.value,
          ),
      }),
      // The memory of the applied operations is empty: the client does not
      // know the identifiers the server gave to the operations it accepted.
      appliedKeys: const <String>{},
    );
  }

  /// Collects the blocks of [raw], roots and children alike.
  static void _collect(Object? raw, List<ServerBlock> into) {
    if (raw is! List<Object?>) return;
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) continue;
      into.add(ServerBlock.fromJson(item));
      _collect(item['children'], into);
    }
  }

  /// Reads the metadata of the tree.
  static Map<String, String> _meta(Object? raw) {
    if (raw is! Map<String, Object?>) return const <String, String>{};
    return Map<String, String>.unmodifiable(<String, String>{
      for (final MapEntry<String, Object?> entry in raw.entries)
        entry.key: entry.value is String ? entry.value! as String : '',
    });
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> json, String column) {
    final Object? value = json[column];
    return value is String ? value : '';
  }

  /// Reads a column of integers, `0` when it is missing.
  static int _integer(Map<String, Object?> json, String column) {
    final Object? value = json[column];
    return value is int ? value : 0;
  }
}

/// A block of the tree of the server.
final class ServerBlock {
  /// Creates a block.
  const ServerBlock({
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
  });

  /// Reads the block from the answer of the API.
  factory ServerBlock.fromJson(Map<String, Object?> json) {
    return ServerBlock(
      id: _text(json, 'id'),
      parentId: json['parent_id'] is String
          ? json['parent_id']! as String
          : null,
      orderKey: _orderKey(json),
      type: _blockType(json),
      content: _text(json, 'content'),
      lamport: _integer(json, 'lamport'),
      authorId: _text(json, 'author_id'),
      deleted: json['deleted'] == true,
      version: _integer(json, 'version'),
      marks: _marks(json['marks']),
    );
  }

  /// The identifier of the block.
  final String id;

  /// The identifier of the parent block, `null` for a root block.
  final String? parentId;

  /// The fractional index of the block among its siblings.
  final OrderKey orderKey;

  /// The kind of the block.
  final BlockType type;

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

  /// The ranges of the marks of the block.
  final Map<String, MarkRange> marks;

  /// The state of the block, as the client stores it.
  BlockState toState() {
    final AuthorId author = AuthorId(authorId);
    final TextContent content = TextContent(this.content);
    return BlockState(
      id: BlockId(id),
      insert: InsertInfo(
        lamport: lamport,
        author: author,
        parent: parentId == null ? null : BlockId(parentId!),
        order: orderKey,
        type: type,
        content: content,
      ),
      // A deleted block keeps no version of its content: the tombstone is
      // the state of the block, and the text it held is gone.
      versions: deleted
          ? const <ContentVersion>[]
          : <ContentVersion>[
              ContentVersion(
                lamport: lamport,
                author: author,
                content: content,
              ),
            ],
      deletedAt: deleted ? lamport : null,
      deletedBy: deleted ? author : null,
      marks: Map<MarkId, MarkState>.unmodifiable(<MarkId, MarkState>{
        for (final MapEntry<String, MarkRange> entry in marks.entries)
          MarkId(entry.key): MarkState(
            addedAt: lamport,
            addedBy: author,
            // The tree carries the range of the marks, not their nature: the
            // client rebuilds them as annotations.
            type: MarkType.comment,
            range: entry.value,
          ),
      }),
      opCount: version,
    );
  }

  /// Reads the order key of the block.
  ///
  /// Throws a [SyncTransportException] when the key is malformed: a server
  /// that answers an unreadable tree is not a server the client can follow.
  static OrderKey _orderKey(Map<String, Object?> json) {
    final String raw = _text(json, 'order_key');
    try {
      return OrderKey(raw.isEmpty ? OrderKey.initial.value : raw);
    } on InvalidSyncOperationException catch (error) {
      throw SyncTransportException(
        'The server answered an unreadable order key: ${error.message}',
        code: 'sync_invalid_payload',
        cause: error,
      );
    }
  }

  /// Reads the kind of the block, a paragraph when it is unknown.
  static BlockType _blockType(Map<String, Object?> json) {
    final String name = _text(json, 'type');
    for (final BlockType type in BlockType.values) {
      if (type.name == name) return type;
    }
    return BlockType.paragraph;
  }

  /// Reads the ranges of the marks of the block.
  static Map<String, MarkRange> _marks(Object? raw) {
    if (raw is! Map<String, Object?>) return const <String, MarkRange>{};
    final Map<String, MarkRange> marks = <String, MarkRange>{};
    for (final MapEntry<String, Object?> entry in raw.entries) {
      final Object? value = entry.value;
      if (value is! Map<String, Object?>) continue;
      final Object? start = value['start'];
      final Object? end = value['end'];
      if (start is! int || end is! int || start < 0 || end < start) continue;
      marks[entry.key] = MarkRange(start: start, end: end);
    }
    return Map<String, MarkRange>.unmodifiable(marks);
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> json, String column) {
    final Object? value = json[column];
    return value is String ? value : '';
  }

  /// Reads a column of integers, `0` when it is missing.
  static int _integer(Map<String, Object?> json, String column) {
    final Object? value = json[column];
    return value is int ? value : 0;
  }
}

/// The decoding of the trees the server answers.
///
/// The route `/v1/projects/<id>/tree` answers the trees of every document
/// of the project: the client reads them when the server refuses its version
/// of the protocol.
abstract final class ServerTree {
  /// Reads the trees of a project from the answer of the API.
  ///
  /// Throws a [SyncTransportException] when the answer is not the list of
  /// the trees the server promised.
  static List<ServerDocumentTree> decode(Object? payload) {
    if (payload is! List<Object?>) {
      throw const SyncTransportException(
        'The server did not return a list of trees.',
        code: 'sync_invalid_payload',
      );
    }
    final List<ServerDocumentTree> trees = <ServerDocumentTree>[];
    for (final Object? item in payload) {
      if (item is! Map<String, Object?>) continue;
      trees.add(ServerDocumentTree.fromJson(item));
    }
    return List<ServerDocumentTree>.unmodifiable(trees);
  }
}
