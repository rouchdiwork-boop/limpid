import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

void main() {
  group('conflict detection', () {
    const doc = DocumentId('doc-conflict');
    const blockId = BlockId('block-1');

    test('two concurrent versions of the same block are reported', () {
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));
      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Base'),
      );
      final base = ContentBase(
        version: VersionRef(lamport: insert.lamport, author: insert.author),
      );
      final updateA = factoryA.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version A'),
        base: base,
      );
      final updateB = factoryB.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version B'),
        base: base,
      );
      final document = CrdtDocument.empty(doc).apply(insert);

      final reports = const ConflictDetector().detect(
        document: document,
        localOperations: <SyncOp>[insert, updateA],
        remoteOperations: <SyncOp>[insert, updateB],
      );

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report.blockId, blockId);
      expect(report.kind, ConflictKind.content);
      expect(report.local.plainText, 'Version A');
      expect(report.remote.plainText, 'Version B');
      expect(report.position.index, 0);
      expect(report.position.order, OrderKey.initial);
    });

    test('a version derived from the other one is not a conflict', () {
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));
      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Base'),
      );
      final first = factoryA.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version A'),
        base: ContentBase(
          version: VersionRef(lamport: insert.lamport, author: insert.author),
        ),
      );
      final second = factoryB.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version B'),
        base: ContentBase(
          version: VersionRef(lamport: first.lamport, author: first.author),
        ),
      );
      final document = CrdtDocument.empty(
        doc,
      ).applyAll(<SyncOp>[insert, first]);

      final reports = const ConflictDetector().detect(
        document: document,
        localOperations: <SyncOp>[insert, first],
        remoteOperations: <SyncOp>[second],
      );

      expect(reports, isEmpty);
    });

    test('the author chooses between the two versions and the merge', () {
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));
      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Base'),
      );
      final base = ContentBase(
        version: VersionRef(lamport: insert.lamport, author: insert.author),
      );
      final updateA = factoryA.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version A'),
        base: base,
      );
      final updateB = factoryB.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version B'),
        base: base,
      );
      final report = const ConflictDetector()
          .detect(
            document: CrdtDocument.empty(doc).apply(insert),
            localOperations: <SyncOp>[insert, updateA],
            remoteOperations: <SyncOp>[insert, updateB],
          )
          .single;
      const resolver = ConflictResolver();

      expect(
        resolver.resolve(report, ConflictResolution.keepLocal).plainText,
        'Version A',
      );
      expect(
        resolver.resolve(report, ConflictResolution.keepRemote).plainText,
        'Version B',
      );
      final merged = resolver.resolve(report, ConflictResolution.merge);
      expect(merged.plainText, contains('Version'));
      expect(merged.plainText, contains('A'));
      expect(merged.plainText, contains('B'));
    });

    test('the resolution chosen by the author is enqueued', () async {
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));
      final client = SyncClient(
        documentId: doc,
        authorId: const AuthorId('author-a'),
        transport: OfflineTransport(),
        queueStore: InMemoryOpQueueStore(),
        snapshotStore: InMemorySnapshotStore(),
        connectivity: FixedConnectivityProbe(false),
      );
      addTearDown(client.dispose);
      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Base'),
      );
      await client.enqueue(insert);
      final base = ContentBase(
        version: VersionRef(lamport: insert.lamport, author: insert.author),
      );
      final updateA = factoryA.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version A'),
        base: base,
      );
      final updateB = factoryB.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Version B'),
        base: base,
      );
      final report = const ConflictDetector()
          .detect(
            document: client.document,
            localOperations: <SyncOp>[insert, updateA],
            remoteOperations: <SyncOp>[insert, updateB],
          )
          .single;

      await client.enqueueConflictResolution(
        report,
        ConflictResolution.keepRemote,
        lamport: 42,
      );

      expect(client.document.blocks.single.content.plainText, 'Version B');
      final pending = await client.queue.pending();
      expect(pending, hasLength(2));
      final resolution = pending.last.operation as UpdateContentOp;
      expect(resolution.lamport, 42);
      expect(resolution.content.plainText, 'Version B');
    });

    test(
      'a strict client refuses to finish a round trip with a conflict',
      () async {
        final server = FakeSyncServer();
        final factoryA = OpFactory(const AuthorId('author-a'));
        final factoryB = OpFactory(const AuthorId('author-b'));
        final clientA = _client(
          doc,
          const AuthorId('author-a'),
          server,
          factoryA,
          failOnConflict: true,
        );
        final clientB = _client(
          doc,
          const AuthorId('author-b'),
          server,
          factoryB,
        );
        addTearDown(clientA.dispose);
        addTearDown(clientB.dispose);

        final insert = factoryA.insertBlock(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Base'),
        );
        await clientA.enqueue(insert);
        await clientA.sync(doc.value);
        await clientB.sync(doc.value);

        final baseA = clientA.document.latestContentVersion(blockId);
        final baseB = clientB.document.latestContentVersion(blockId);
        await clientA.enqueue(
          factoryA.updateContent(
            doc: doc,
            blockId: blockId,
            content: const TextContent('Version A'),
            base: ContentBase(version: baseA!),
          ),
        );
        await clientB.enqueue(
          factoryB.updateContent(
            doc: doc,
            blockId: blockId,
            content: const TextContent('Version B'),
            base: ContentBase(version: baseB!),
          ),
        );

        await expectLater(
          clientA.sync(doc.value),
          throwsA(
            isA<SyncConflictException>().having(
              (error) => error.reports,
              'reports',
              isNotEmpty,
            ),
          ),
        );
        expect(clientA.state.status, SyncStatus.error);
      },
    );

    test('the client publishes the conflicts it detects', () async {
      final server = FakeSyncServer();
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));
      final clientA = _client(
        doc,
        const AuthorId('author-a'),
        server,
        factoryA,
      );
      final clientB = _client(
        doc,
        const AuthorId('author-b'),
        server,
        factoryB,
      );
      addTearDown(clientA.dispose);
      addTearDown(clientB.dispose);

      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Base'),
      );
      await clientA.enqueue(insert);
      await clientA.sync(doc.value);
      await clientB.sync(doc.value);

      final conflicts = <ConflictReport>[];
      final subscription = clientA.watch(doc.value).listen((event) {
        if (event is SyncConflictDetected) conflicts.addAll(event.reports);
      });
      addTearDown(subscription.cancel);

      final baseA = clientA.document.latestContentVersion(blockId);
      final baseB = clientB.document.latestContentVersion(blockId);
      await clientA.enqueue(
        factoryA.updateContent(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Version A'),
          base: ContentBase(version: baseA!),
        ),
      );
      await clientB.enqueue(
        factoryB.updateContent(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Version B'),
          base: ContentBase(version: baseB!),
        ),
      );

      await clientA.sync(doc.value);
      await clientB.sync(doc.value);
      await Future<void>.delayed(Duration.zero);

      expect(conflicts, isNotEmpty);
      expect(conflicts.first.blockId, blockId);
      expect(conflicts.first.local.plainText, 'Version A');
      expect(conflicts.first.remote.plainText, 'Version B');
    });
  });
}

SyncClient _client(
  DocumentId doc,
  AuthorId author,
  FakeSyncServer server,
  OpFactory factory, {
  bool failOnConflict = false,
}) {
  final client = SyncClient(
    documentId: doc,
    authorId: author,
    transport: FakeSyncTransport(server),
    queueStore: InMemoryOpQueueStore(),
    snapshotStore: InMemorySnapshotStore(),
    connectivity: FixedConnectivityProbe(true),
    failOnConflict: failOnConflict,
  );
  client.watch(doc.value).listen((event) {
    if (event is SyncRemoteOpApplied) factory.observe(event.operation);
  });
  return client;
}
