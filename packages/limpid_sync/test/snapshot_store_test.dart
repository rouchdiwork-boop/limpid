import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

void main() {
  group('snapshot store', () {
    const doc = DocumentId('doc-snapshot');
    final operations = <SyncOp>[
      InsertBlockOp(
        doc: doc,
        lamport: 1,
        author: const AuthorId('author-a'),
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Premier.'),
      ),
      UpdateContentOp(
        doc: doc,
        lamport: 2,
        author: const AuthorId('author-a'),
        blockId: const BlockId('block-1'),
        content: const TextContent('Second.'),
      ),
    ];

    test('the snapshot restores the exact state of the document', () {
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 5,
        maxLamport: 2,
        operations: operations,
      );

      final restored = snapshot.restore();

      expect(restored.blocks, hasLength(1));
      expect(restored.blocks.single.content.plainText, 'Second.');
      expect(restored.operationCount, 2);
      expect(restored.hasApplied(operations.last), isTrue);
    });

    test('the snapshot survives a JSON round trip', () {
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 5,
        maxLamport: 2,
        operations: operations,
      );

      final decoded = DocumentSnapshot.fromJson(snapshot.toJson());

      expect(decoded.documentId, doc);
      expect(decoded.since, 5);
      expect(decoded.maxLamport, 2);
      expect(decoded.operations, operations);
    });

    test('the in-memory store keeps the snapshots of the documents', () async {
      final store = InMemorySnapshotStore();
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 1,
        maxLamport: 1,
        operations: operations,
      );

      expect(await store.read(doc), isNull);
      await store.write(snapshot);
      expect((await store.read(doc))!.since, 1);
      await store.remove(doc);
      expect(await store.read(doc), isNull);
    });
  });
}
