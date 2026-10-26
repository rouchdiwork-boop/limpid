import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

const DocumentId _documentId = DocumentId('document-engine');
const AuthorId _authorId = AuthorId('writer-a');

/// An in-memory transport standing for the API.
final class _MemoryTransport implements SyncTransport {
  final List<SyncOp> server = <SyncOp>[];
  int pushCount = 0;

  @override
  Future<List<SyncOp>> push(List<SyncOp> operations) async {
    pushCount++;
    server.addAll(operations);
    return operations;
  }

  @override
  Future<List<SyncOp>> pull({required int since}) async {
    return server.where((op) => op.lamport > since).toList();
  }
}

void main() {
  group('SyncEngine', () {
    test('starts with an empty document and no pending operation', () {
      final engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      expect(engine.document.blocks, isEmpty);
      expect(engine.pendingOperations, isEmpty);
      expect(engine.hasPendingOperations, isFalse);
    });

    test('queues a local operation and applies it to the document', () {
      var engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      engine = engine.insertBlock(
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      expect(engine.pendingOperations, hasLength(1));
      expect(engine.hasPendingOperations, isTrue);
      expect(engine.document.blocks, hasLength(1));
      expect(engine.document.blocks.single.content.plainText, 'Bonjour');
      expect(engine.clock.current, 1);
    });

    test('never mutates the engine it is called on', () {
      final engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      engine.insertBlock(
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      expect(engine.pendingOperations, isEmpty);
      expect(engine.document.blocks, isEmpty);
    });

    test('ignores a remote operation that was already applied', () {
      var engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      final op = InsertBlockOp(
        doc: _documentId,
        lamport: 7,
        author: const AuthorId('writer-b'),
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      engine = engine.applyRemote(op);
      final afterFirst = engine.document;
      engine = engine.applyRemote(op);
      expect(engine.document.blocks, afterFirst.blocks);
      expect(engine.document.operationCount, afterFirst.operationCount);
    });

    test('pushes the pending operations and clears the queue', () async {
      final transport = _MemoryTransport();
      var engine = SyncEngine(
        documentId: _documentId,
        authorId: _authorId,
        transport: transport,
      );
      engine = engine.insertBlock(
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      final result = await engine.sync();
      expect(result.report.pushed, 1);
      // The pushed operation comes back from the pull: it is already known
      // and must not be applied twice.
      expect(result.report.duplicates, 2);
      expect(result.report.applied, 0);
      expect(result.engine.pendingOperations, isEmpty);
      expect(transport.server, hasLength(1));
      expect(result.engine.document.blocks, hasLength(1));
    });

    test('pulls the remote operations and merges them', () async {
      final transport = _MemoryTransport();
      final engine = SyncEngine(
        documentId: _documentId,
        authorId: _authorId,
        transport: transport,
      );
      transport.server.add(
        InsertBlockOp(
          doc: _documentId,
          lamport: 3,
          author: const AuthorId('writer-b'),
          blockId: const BlockId('block-remote'),
          parent: null,
          order: OrderKey('95'),
          type: BlockType.paragraph,
          content: const TextContent('Distant'),
        ),
      );
      final result = await engine.sync();
      expect(result.report.pulled, 1);
      expect(result.report.applied, 1);
      expect(result.engine.document.blocks, hasLength(1));
      expect(result.engine.document.blocks.single.content.plainText, 'Distant');
    });

    test('refuses to synchronise without a transport', () {
      final engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      expect(
        () => engine.sync(),
        throwsA(isA<InvalidSyncOperationException>()),
      );
    });

    test('rejects an operation that targets another document', () {
      final engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      final op = InsertBlockOp(
        doc: const DocumentId('another-document'),
        lamport: 1,
        author: _authorId,
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      expect(
        () => engine.applyRemote(op),
        throwsA(isA<InvalidSyncOperationException>()),
      );
    });

    test('bases a local update on the latest known version', () {
      var engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      engine = engine.insertBlock(
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Bonjour'),
      );
      engine = engine.updateContent(
        blockId: const BlockId('block-1'),
        content: const TextContent('Bonjour le monde'),
      );
      final update = engine.pendingOperations.last as UpdateContentOp;
      expect(update.base, isNotNull);
      expect(update.base!.version.lamport, 1);
      expect(update.base!.version.author, _authorId);
    });

    test('generates sortable identifiers', () {
      final engine = SyncEngine(documentId: _documentId, authorId: _authorId);
      final first = engine.nextId<BlockTag>();
      final second = engine.nextId<BlockTag>();
      expect(second.value.compareTo(first.value), isPositive);
    });
  });
}
