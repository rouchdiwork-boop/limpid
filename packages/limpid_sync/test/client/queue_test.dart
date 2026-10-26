import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

void main() {
  group('operation queue', () {
    test('a failed operation is retried, survives a restart and is not sent '
        'twice', () async {
      const doc = DocumentId('doc-queue');
      const author = AuthorId('author-a');
      final server = FakeSyncServer();
      final store = InMemoryOpQueueStore();
      final factory = OpFactory(author);
      final operation = factory.insertBlock(
        doc: doc,
        blockId: const BlockId('block-1'),
        content: const TextContent('Hello'),
      );

      // The first push fails: the operation stays in the queue.
      server.failingPushes = 1;
      final firstTransport = FakeSyncTransport(server);
      final firstClient = SyncClient(
        documentId: doc,
        authorId: author,
        transport: firstTransport,
        queueStore: store,
        snapshotStore: InMemorySnapshotStore(),
        queue: OpQueue(store: store, retryPolicy: RetryPolicy.immediate),
        connectivity: FixedConnectivityProbe(true),
      );
      await firstClient.enqueue(operation);
      await firstClient.dispose();

      final entries = await store.all();
      expect(entries, hasLength(1));
      expect(entries.single.status, OpQueueStatus.failed);
      expect(entries.single.attempts, 1);
      expect(entries.single.operation, operation);

      // The application restarts: a new client is built on the same store.
      final secondTransport = FakeSyncTransport(server);
      final secondClient = SyncClient(
        documentId: doc,
        authorId: author,
        transport: secondTransport,
        queueStore: store,
        snapshotStore: InMemorySnapshotStore(),
        queue: OpQueue(store: store, retryPolicy: RetryPolicy.immediate),
        connectivity: FixedConnectivityProbe(true),
      );
      addTearDown(secondClient.dispose);

      await secondClient.sync(doc.value);

      expect(secondTransport.pushes, hasLength(1));
      expect(secondTransport.pushes.single.single, operation);
      expect(secondClient.pendingCount, 0);
      expect(await store.all(), isEmpty);

      // The operation is not sent a second time.
      await secondClient.sync(doc.value);
      expect(secondTransport.pushes, hasLength(1));
    });

    test(
      'the queue is idempotent: the same operation is stored once',
      () async {
        const doc = DocumentId('doc-idempotent');
        final store = InMemoryOpQueueStore();
        final queue = OpQueue(store: store, retryPolicy: RetryPolicy.immediate);
        final factory = OpFactory(const AuthorId('author-a'));
        final operation = factory.insertBlock(
          doc: doc,
          blockId: const BlockId('block-1'),
        );

        await queue.enqueue(operation);
        await queue.enqueue(operation);

        expect(await store.all(), hasLength(1));
      },
    );

    test('the failed operations are retried after the backoff', () async {
      const doc = DocumentId('doc-backoff');
      final store = InMemoryOpQueueStore();
      var now = DateTime(2026, 10, 25, 9);
      final queue = OpQueue(
        store: store,
        retryPolicy: const RetryPolicy(
          baseDelay: Duration(seconds: 30),
          maxDelay: Duration(minutes: 5),
          jitterRatio: 0,
        ),
        now: () => now,
      );
      final factory = OpFactory(const AuthorId('author-a'));
      final operation = factory.insertBlock(
        doc: doc,
        blockId: const BlockId('block-1'),
      );
      await queue.enqueue(operation);
      final entry = (await store.all()).single;

      await queue.markFailed(entry, reason: 'The API is unreachable.');

      final failed = (await store.all()).single;
      expect(failed.status, OpQueueStatus.failed);
      expect(failed.attempts, 1);
      expect(failed.nextAttemptAt, now.add(const Duration(seconds: 30)));
      expect(await queue.ready(), isEmpty);

      now = now.add(const Duration(seconds: 31));
      expect(await queue.ready(), hasLength(1));
    });

    test(
      'the pending operations are sent by increasing Lamport timestamp',
      () async {
        const doc = DocumentId('doc-order');
        final store = InMemoryOpQueueStore();
        final queue = OpQueue(store: store, retryPolicy: RetryPolicy.immediate);
        final factory = OpFactory(const AuthorId('author-a'));
        final first = factory.insertBlock(
          doc: doc,
          blockId: const BlockId('b1'),
        );
        final second = factory.insertBlock(
          doc: doc,
          blockId: const BlockId('b2'),
        );
        final third = factory.insertBlock(
          doc: doc,
          blockId: const BlockId('b3'),
        );
        await queue.enqueue(third);
        await queue.enqueue(first);
        await queue.enqueue(second);

        final ready = await queue.ready();

        expect(
          ready.map((entry) => entry.operation),
          equals(<SyncOp>[first, second, third]),
        );
      },
    );
  });
}
