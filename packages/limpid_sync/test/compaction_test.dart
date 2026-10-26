import 'dart:convert';

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import 'support/fake_server.dart';
import 'support/ops.dart';

void main() {
  group('compaction of the journal', () {
    const doc = DocumentId('doc-compaction');

    /// A journal of [updates] modifications of a single block.
    List<SyncOp> journalOf({int updates = 600}) {
      final factory = OpFactory(const AuthorId('author-a'));
      return <SyncOp>[
        factory.insertBlock(
          doc: doc,
          blockId: const BlockId('block-1'),
          content: const TextContent('Premier.'),
        ),
        for (var index = 0; index < updates; index++)
          factory.updateContent(
            doc: doc,
            blockId: const BlockId('block-1'),
            content: TextContent('Texte $index'),
          ),
      ];
    }

    test('the state restored after the compaction is the state before', () {
      final operations = journalOf();
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: operations,
      );
      final before = snapshot.restore();

      final report = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: const <String>{},
      );
      final after = report.snapshot.restore();

      expect(report.compactedOperations, operations.length);
      expect(after.blocks, equals(before.blocks));
      expect(after.meta, equals(before.meta));
      expect(after.operationCount, before.operationCount);
    });

    test('the compaction purges the journal and the payload shrinks', () {
      final operations = journalOf();
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: operations,
      );

      final report = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: const <String>{},
      );

      expect(report.snapshot.operations, isEmpty);
      expect(report.snapshot.state, isNotNull);
      final String compacted = jsonEncode(report.snapshot.toJson());
      final String journal = jsonEncode(snapshot.toJson());
      expect(compacted.length, lessThan(journal.length));
    });

    test('compacting twice gives the same result', () {
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: journalOf(),
      );

      final first = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: const <String>{},
      );
      final second = const JournalCompactor().compact(
        first.snapshot,
        unsyncedKeys: const <String>{},
      );

      expect(second.compactedOperations, 0);
      expect(second.snapshot.toJson(), equals(first.snapshot.toJson()));
    });

    test('compacting twice gives the same result when an operation waits', () {
      final operations = journalOf();
      final String unsynced = operations.last.operationKey;
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: operations,
      );

      final first = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: <String>{unsynced},
      );
      final second = const JournalCompactor().compact(
        first.snapshot,
        unsyncedKeys: <String>{unsynced},
      );

      expect(second.compactedOperations, 0);
      expect(second.snapshot.toJson(), equals(first.snapshot.toJson()));
    });

    test('an operation the server did not accept is never purged', () {
      final operations = journalOf();
      final String unsynced = operations.last.operationKey;
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: operations,
      );
      final before = snapshot.restore();

      final report = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: <String>{unsynced},
      );

      expect(
        report.snapshot.operations.map(
          (SyncOp operation) => operation.operationKey,
        ),
        contains(unsynced),
      );
      expect(report.compactedOperations, operations.length - 1);
      expect(report.snapshot.restore().blocks, equals(before.blocks));
    });

    test('the journal is left alone below the threshold', () {
      final operations = journalOf(updates: 10);
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 11,
        operations: operations,
      );

      final report = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: const <String>{},
      );

      expect(report.compactedOperations, 0);
      expect(report.snapshot.operations, hasLength(operations.length));
      expect(report.snapshot.state, isNull);
    });

    test('the compacted state survives a JSON round trip', () {
      final snapshot = DocumentSnapshot(
        documentId: doc,
        since: 12,
        maxLamport: 601,
        operations: journalOf(),
      );
      final report = const JournalCompactor().compact(
        snapshot,
        unsyncedKeys: const <String>{},
      );

      final decoded = DocumentSnapshot.fromJson(
        jsonDecode(jsonEncode(report.snapshot.toJson()))
            as Map<String, Object?>,
      );

      expect(decoded.operations, isEmpty);
      expect(
        decoded.restore().blocks,
        equals(report.snapshot.restore().blocks),
      );
    });

    test('the client compacts the journal the server accepted', () async {
      const clientDoc = DocumentId('doc-client-compaction');
      final server = FakeSyncServer();
      final snapshots = InMemorySnapshotStore();
      final client = SyncClient(
        documentId: clientDoc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: snapshots,
        compactor: const JournalCompactor(threshold: 5),
      );
      addTearDown(client.dispose);
      final factory = OpFactory(const AuthorId('author-a'));

      for (var index = 0; index < 6; index++) {
        await client.enqueue(
          factory.insertBlock(
            doc: clientDoc,
            blockId: BlockId('block-$index'),
            content: TextContent('Bloc $index'),
          ),
        );
      }

      final snapshot = await snapshots.read(clientDoc);
      expect(snapshot, isNotNull);
      expect(snapshot!.state, isNotNull);
      // The journal only holds the operations applied after the last
      // compaction: it does not grow any more.
      expect(snapshot.operations.length, lessThan(6));
      expect(snapshot.restore().blocks, hasLength(6));
    });

    test('the resume after a cut restores the same state', () async {
      const clientDoc = DocumentId('doc-resume');
      final server = FakeSyncServer();
      final snapshots = InMemorySnapshotStore();
      final factory = OpFactory(const AuthorId('author-a'));
      final client = SyncClient(
        documentId: clientDoc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: snapshots,
        compactor: const JournalCompactor(threshold: 3),
      );
      addTearDown(client.dispose);

      await client.enqueue(
        factory.insertBlock(
          doc: clientDoc,
          blockId: const BlockId('block-1'),
          content: const TextContent('Premier.'),
        ),
      );
      VersionRef? base;
      for (var index = 0; index < 5; index++) {
        final UpdateContentOp update = factory.updateContent(
          doc: clientDoc,
          blockId: const BlockId('block-1'),
          content: TextContent('Version $index'),
          base: base == null ? null : ContentBase(version: base),
        );
        base = VersionRef(lamport: update.lamport, author: update.author);
        await client.enqueue(update);
      }
      final before = client.document.blocks;

      // L'application est fermee et rouverte : le client lit l'instantane
      // compacte et reconstruit le document.
      await client.dispose();
      final resumed = SyncClient(
        documentId: clientDoc,
        authorId: const AuthorId('author-a'),
        transport: FakeSyncTransport(server),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: snapshots,
        compactor: const JournalCompactor(threshold: 3),
      );
      addTearDown(resumed.dispose);
      await resumed.restore();

      expect(resumed.document.blocks, equals(before));
      expect(resumed.document.blocks.single.content.plainText, 'Version 4');
    });
  });
}
