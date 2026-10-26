import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

void main() {
  group('client events', () {
    const doc = DocumentId('doc-events');
    final factory = OpFactory(const AuthorId('author-a'));

    test('the local and the remote operations are published', () async {
      final server = FakeSyncServer();
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);
      final events = <SyncEvent>[];
      final subscription = client.watch(doc.value).listen(events.add);
      addTearDown(subscription.cancel);

      final operation = factory.insertBlock(
        doc: doc,
        blockId: const BlockId('block-1'),
        content: const TextContent('Local'),
      );
      await client.enqueue(operation);
      await Future<void>.delayed(Duration.zero);

      final remote = OpFactory(const AuthorId('author-b')).insertBlock(
        doc: doc,
        blockId: const BlockId('block-2'),
        content: const TextContent('Distant'),
      );
      await server.push(<SyncOp>[remote]);
      await client.sync(doc.value);
      await Future<void>.delayed(Duration.zero);

      final local = events.whereType<SyncLocalOpApplied>().toList();
      final remoteEvents = events.whereType<SyncRemoteOpApplied>().toList();
      expect(local, hasLength(1));
      expect(local.single.operation, operation);
      expect(remoteEvents, hasLength(1));
      expect(remoteEvents.single.operation, remote);
      expect(events.whereType<SyncStateChanged>(), isNotEmpty);
    });

    test('the events of another document are filtered out', () async {
      final server = FakeSyncServer();
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);
      final events = <SyncEvent>[];
      final subscription = client.watch('another-document').listen(events.add);
      addTearDown(subscription.cancel);

      await client.enqueue(
        factory.insertBlock(doc: doc, blockId: const BlockId('block-1')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('an operation of another document is rejected', () async {
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(FakeSyncServer()),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(client.dispose);
      final operation = OpFactory(const AuthorId('author-a')).insertBlock(
        doc: const DocumentId('another-document'),
        blockId: const BlockId('block-1'),
      );

      expect(
        () => client.enqueue(operation),
        throwsA(isA<SyncTransportException>()),
      );
    });
  });
}
