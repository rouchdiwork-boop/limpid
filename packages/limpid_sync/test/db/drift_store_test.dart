import 'package:drift/native.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

void main() {
  group('Drift stores', () {
    const doc = DocumentId('doc-drift');
    final operation = InsertBlockOp(
      doc: doc,
      lamport: 4,
      author: const AuthorId('author-a'),
      blockId: const BlockId('block-1'),
      parent: null,
      order: OrderKey.initial,
      type: BlockType.paragraph,
      content: const TextContent('Persisté.'),
    );

    late SyncDatabase database;

    setUp(() {
      database = SyncDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('the queue survives a round trip through SQLite', () async {
      final store = DriftOpQueueStore(database);
      final entry = QueuedOp.pending(
        operation,
        createdAt: DateTime(2026, 10, 25),
      );

      await store.put(entry);

      final found = await store.find(operation.operationKey);
      expect(found, isNotNull);
      expect(found!.operation, operation);
      expect(found.status, OpQueueStatus.pending);
      expect(found.attempts, 0);

      await store.put(
        entry.copyWith(
          status: OpQueueStatus.failed,
          attempts: 2,
          lastError: 'The API is unreachable.',
          nextAttemptAt: DateTime(2026, 10, 26),
        ),
      );
      final failed = await store.find(operation.operationKey);
      expect(failed!.status, OpQueueStatus.failed);
      expect(failed.attempts, 2);
      expect(failed.lastError, 'The API is unreachable.');
      expect(failed.nextAttemptAt, DateTime(2026, 10, 26));

      await store.remove(operation.operationKey);
      expect(await store.find(operation.operationKey), isNull);
    });

    test('the queue publishes its content when it changes', () async {
      final store = DriftOpQueueStore(database);
      final events = <List<QueuedOp>>[];
      final subscription = store.watch().listen(events.add);
      addTearDown(subscription.cancel);

      await store.put(QueuedOp.pending(operation));

      await _pump();
      expect(events, isNotEmpty);
      expect(events.last, hasLength(1));
      expect(events.last.single.operation, operation);
    });

    test('the snapshot survives a round trip through SQLite', () async {
      final store = DriftSnapshotStore(database);
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 7,
        maxLamport: 12,
        operations: <SyncOp>[operation],
      );

      await store.write(snapshot);

      final restored = await store.read(doc);
      expect(restored, isNotNull);
      expect(restored!.since, 7);
      expect(restored.maxLamport, 12);
      expect(restored.operations.single, operation);
      expect(restored.restore().blocks, hasLength(1));

      await store.remove(doc);
      expect(await store.read(doc), isNull);
    });
  });
}

/// Lets the pending microtasks run.
Future<void> _pump() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
