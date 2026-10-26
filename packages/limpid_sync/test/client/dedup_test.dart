import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

void main() {
  group('deduplication', () {
    test('an operation enqueued twice is pushed and applied once', () async {
      const doc = DocumentId('doc-dedup');
      final server = FakeSyncServer();
      final transport = FakeSyncTransport(server);
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: transport,
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);
      final factory = OpFactory(const AuthorId('author-a'));
      final operation = factory.insertBlock(
        doc: doc,
        blockId: const BlockId('block-1'),
        content: const TextContent('Hello'),
      );

      await client.enqueue(operation);
      await client.enqueue(operation);
      await client.sync(doc.value);

      expect(transport.pushes, hasLength(1));
      expect(transport.pushes.single, hasLength(1));
      expect(client.document.operationCount, 1);
      expect(client.document.blocks, hasLength(1));
      expect(client.pendingCount, 0);
    });

    test('an operation received twice by pull is applied once', () async {
      const doc = DocumentId('doc-pull-dedup');
      final factory = OpFactory(const AuthorId('author-b'));
      final operation = factory.insertBlock(
        doc: doc,
        blockId: const BlockId('block-1'),
        content: const TextContent('Remote'),
      );
      final transport = StaticTransport(<SyncOp>[operation]);
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: transport,
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);

      await client.sync(doc.value);
      await client.sync(doc.value);
      await client.sync(doc.value);

      expect(client.document.operationCount, 1);
      expect(client.document.blocks, hasLength(1));
    });

    test('the client resumes on the cursor of the last pull', () async {
      const doc = DocumentId('doc-cursor');
      final server = FakeSyncServer();
      final transport = FakeSyncTransport(server);
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: transport,
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);
      final factory = OpFactory(const AuthorId('author-a'));

      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-1')),
      );
      await client.sync(doc.value);
      expect(client.since, 1);

      // Nothing new on the server: the cursor does not move.
      await client.sync(doc.value);
      expect(client.since, 1);

      // A new operation reaches the server.
      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-2')),
      );
      await client.sync(doc.value);
      expect(client.since, 2);
      expect(client.document.blocks, hasLength(2));
    });

    test('the document and the cursor survive a restart', () async {
      const doc = DocumentId('doc-restart');
      final server = FakeSyncServer();
      final snapshots = InMemorySnapshotStore();
      final factory = OpFactory(const AuthorId('author-a'));

      final firstClient = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: snapshots,
        connectivity: FixedConnectivityProbe(true),
      );
      await firstClient.enqueue(
        factory.insertBlock(
          doc: doc,
          blockId: const BlockId('block-1'),
          content: const TextContent('Persisted'),
        ),
      );
      await firstClient.sync(doc.value);
      await firstClient.dispose();

      final secondClient = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: snapshots,
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(secondClient.dispose);
      await secondClient.restore();

      expect(secondClient.document.blocks, hasLength(1));
      expect(
        secondClient.document.blocks.single.content.plainText,
        'Persisted',
      );
      expect(secondClient.since, 1);
      expect(secondClient.maxLamport, 1);
    });
  });
}
