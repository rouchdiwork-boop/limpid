import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

void main() {
  group('offline mode', () {
    test('enqueue does not throw and the queue grows when offline', () async {
      const doc = DocumentId('doc-offline');
      final transport = OfflineTransport();
      final probe = FixedConnectivityProbe(false);
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: transport,
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: probe,
      );
      addTearDown(client.dispose);
      final factory = OpFactory(const AuthorId('author-a'));

      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-1')),
      );
      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-2')),
      );
      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-3')),
      );

      expect(transport.pushCount, 0);
      expect(client.state.status, SyncStatus.offline);
      expect(client.state.isOnline, isFalse);
      expect(client.pendingCount, 3);
      expect(client.document.blocks, hasLength(3));
    });

    test('an unreachable API switches the client to offline', () async {
      const doc = DocumentId('doc-unreachable');
      final transport = OfflineTransport();
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

      expect(client.state.status, SyncStatus.offline);
      expect(client.pendingCount, 1);
      expect(transport.pushCount, 1);
    });

    test('sync reports the offline state instead of throwing', () async {
      const doc = DocumentId('doc-sync-offline');
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: OfflineTransport(),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(false),
      );
      addTearDown(client.dispose);

      final report = await client.sync(doc.value);

      expect(report.pushed, 0);
      expect(report.pulled, 0);
      expect(client.state.status, SyncStatus.offline);
    });

    test(
      'the network status change is published on the event stream',
      () async {
        const doc = DocumentId('doc-events');
        final probe = FixedConnectivityProbe(true);
        final client = SyncClient(
          documentId: doc,
          authorId: const AuthorId('author-a'),
          transport: OfflineTransport(),
          queueStore: InMemoryOpQueueStore(),
          snapshotStore: InMemorySnapshotStore(),
          connectivity: probe,
        );
        addTearDown(client.dispose);
        final events = <SyncEvent>[];
        final subscription = client.watch(doc.value).listen(events.add);
        addTearDown(subscription.cancel);

        probe.online = false;
        await client.sync(doc.value);

        expect(
          events.whereType<SyncNetworkStatusChanged>().map((e) => e.isOnline),
          containsAllInOrder(<bool>[false]),
        );
      },
    );
  });
}
