import 'dart:math';

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/ops.dart';

/// The most important test of the package: two replicas that write at the
/// same time, offline, and converge on exactly the same document once the
/// network comes back — whatever the order of the delivery.
void main() {
  group('convergence', () {
    test('two clients converge on an identical document', () async {
      final random = Random(20261025);
      final server = FakeSyncServer(random: Random(4242));
      const doc = DocumentId('doc-convergence');
      const authorA = AuthorId('author-a');
      const authorB = AuthorId('author-b');
      final factoryA = OpFactory(authorA);
      final factoryB = OpFactory(authorB);

      final clientA = _buildClient(doc, authorA, server, factoryA);
      final clientB = _buildClient(doc, authorB, server, factoryB);
      addTearDown(clientA.dispose);
      addTearDown(clientB.dispose);

      final blocks = <BlockId>[
        const BlockId('block-1'),
        const BlockId('block-2'),
        const BlockId('block-3'),
      ];

      // Eight rounds of concurrent writing: both authors work offline during
      // a round, then the network comes back and the replicas exchange their
      // operations in a random order.
      for (var round = 0; round < 8; round++) {
        final opsA = _writeRound(
          factory: factoryA,
          client: clientA,
          doc: doc,
          blocks: blocks,
          random: random,
          salt: 'a$round',
        );
        final opsB = _writeRound(
          factory: factoryB,
          client: clientB,
          doc: doc,
          blocks: blocks,
          random: random,
          salt: 'b$round',
        );

        for (final op in opsA) {
          await clientA.enqueue(op);
        }
        for (final op in opsB) {
          await clientB.enqueue(op);
        }

        if (random.nextBool()) {
          await clientA.sync(doc.value);
          await clientB.sync(doc.value);
        } else {
          await clientB.sync(doc.value);
          await clientA.sync(doc.value);
        }
      }

      // Let the last operations flow.
      for (var round = 0; round < 5; round++) {
        await clientA.sync(doc.value);
        await clientB.sync(doc.value);
      }

      expect(clientA.pendingCount, 0);
      expect(clientB.pendingCount, 0);
      // Every operation published on the server reached both replicas.
      expect(server.log, isNotEmpty);
      expect(clientA.document.operationCount, server.log.length);
      expect(clientB.document.operationCount, server.log.length);
      expect(clientA.document.blocks, equals(clientB.document.blocks));
      expect(clientA.document.meta, equals(clientB.document.meta));
      expect(clientA.document.blocks, isNotEmpty);
    });

    test(
      'the replicas converge even when the operations are replayed',
      () async {
        final server = FakeSyncServer(random: Random(7));
        const doc = DocumentId('doc-replay');
        const authorA = AuthorId('author-a');
        const authorB = AuthorId('author-b');
        final factoryA = OpFactory(authorA);
        final factoryB = OpFactory(authorB);
        final clientA = _buildClient(doc, authorA, server, factoryA);
        final clientB = _buildClient(doc, authorB, server, factoryB);
        addTearDown(clientA.dispose);
        addTearDown(clientB.dispose);

        const blockId = BlockId('block-1');
        final opA = factoryA.insertBlock(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Version A'),
        );
        final opB = factoryB.insertBlock(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Version B'),
        );
        await clientA.enqueue(opA);
        await clientB.enqueue(opB);
        await clientA.sync(doc.value);
        await clientB.sync(doc.value);
        // The same operations are delivered twice.
        await clientA.sync(doc.value);
        await clientB.sync(doc.value);

        expect(clientA.document.blocks, equals(clientB.document.blocks));
        expect(clientA.document.operationCount, 2);
        expect(clientB.document.operationCount, 2);
      },
    );
  });
}

SyncClient _buildClient(
  DocumentId doc,
  AuthorId author,
  FakeSyncServer server,
  OpFactory factory,
) {
  final client = SyncClient(
    documentId: doc,
    authorId: author,
    transport: FakeSyncTransport(server),
    queueStore: InMemoryOpQueueStore(),
    snapshotStore: InMemorySnapshotStore(),
    connectivity: FixedConnectivityProbe(true),
  );
  // The Lamport clock of the author follows the operations received from the
  // server, exactly like the `SyncEngine` of `limpid_core` does.
  client.watch(doc.value).listen((event) {
    if (event is SyncRemoteOpApplied) factory.observe(event.operation);
  });
  return client;
}

/// Writes a round of operations without synchronising, so the versions of the
/// two authors are genuinely concurrent.
List<SyncOp> _writeRound({
  required OpFactory factory,
  required SyncClient client,
  required DocumentId doc,
  required List<BlockId> blocks,
  required Random random,
  required String salt,
}) {
  final operations = <SyncOp>[];
  final count = 1 + random.nextInt(2);
  for (var index = 0; index < count; index++) {
    final blockId = blocks[random.nextInt(blocks.length)];
    final known = client.document.blocks.any((block) => block.id == blockId);
    if (!known) {
      operations.add(
        factory.insertBlock(
          doc: doc,
          blockId: blockId,
          content: TextContent('$salt ${random.nextInt(10000)}'),
        ),
      );
      continue;
    }
    final base = client.document.latestContentVersion(blockId);
    operations.add(
      factory.updateContent(
        doc: doc,
        blockId: blockId,
        content: TextContent('$salt ${random.nextInt(10000)}'),
        base: base == null ? null : ContentBase(version: base),
      ),
    );
  }
  operations.add(
    factory.setMeta(
      doc: doc,
      key: 'title',
      value: '$salt ${random.nextInt(100)}',
    ),
  );
  return operations;
}
