import 'dart:math' as math;

import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

/// Number of seeds exercised by the fuzz test.
const int _seedCount = 25;

/// Number of rounds played by each seed.
const int _roundCount = 12;

const DocumentId _documentId = DocumentId('document-fuzz');

/// A writer of the fuzz test: it owns a local replica and produces
/// operations from its own point of view.
final class _Writer {
  _Writer(this.authorId, this.random);

  final AuthorId authorId;
  final math.Random random;

  CrdtDocument document = CrdtDocument.empty(_documentId);
  LamportClock clock = const LamportClock();
  final List<SyncOp> produced = <SyncOp>[];
  int _blockCounter = 0;

  /// Applies an operation received from the relay.
  void receive(SyncOp op) {
    if (document.hasApplied(op)) return;
    document = document.apply(op);
    clock = clock.receive(op.lamport);
  }

  /// Produces one operation from the local point of view.
  SyncOp? produce() {
    clock = clock.tick();
    final lamport = clock.current;
    final blocks = document.blocks.where((block) => !block.deleted).toList();
    final action = random.nextInt(8);
    if (blocks.isEmpty || action == 0) {
      return _insert(lamport, blocks);
    }
    final block = blocks[random.nextInt(blocks.length)];
    if (action == 1) {
      return _update(lamport, block);
    }
    if (action == 2) {
      return _move(lamport, block, blocks);
    }
    if (action == 3) {
      return DeleteBlockOp(
        doc: _documentId,
        lamport: lamport,
        author: authorId,
        blockId: block.id,
      );
    }
    if (action == 4) {
      return SetMetaOp(
        doc: _documentId,
        lamport: lamport,
        author: authorId,
        key: 'title',
        value: 'title-$lamport',
      );
    }
    if (action == 5) {
      return AddMarkOp(
        doc: _documentId,
        lamport: lamport,
        author: authorId,
        markId: MarkId('mark-${authorId.value}-$lamport'),
        blockId: block.id,
        type: MarkType.comment,
        range: MarkRange(start: 0, end: 1),
        body: 'note $lamport',
      );
    }
    if (action == 6) {
      final markId = MarkId('mark-${authorId.value}-$lamport');
      return RemoveMarkOp(
        doc: _documentId,
        lamport: lamport,
        author: authorId,
        markId: markId,
        blockId: block.id,
      );
    }
    return _update(lamport, block);
  }

  SyncOp _insert(int lamport, List<Block> blocks) {
    _blockCounter++;
    final parent = blocks.isEmpty
        ? null
        : blocks[random.nextInt(blocks.length)].id;
    return InsertBlockOp(
      doc: _documentId,
      lamport: lamport,
      author: authorId,
      blockId: BlockId('$authorId.value-block-$_blockCounter'),
      parent: parent,
      order: OrderKey('${_blockCounter}5'),
      type: BlockType.paragraph,
      content: TextContent('bloc $_blockCounter'),
    );
  }

  SyncOp _update(int lamport, Block block) {
    final base = document.latestContentVersion(block.id);
    return UpdateContentOp(
      doc: _documentId,
      lamport: lamport,
      author: authorId,
      blockId: block.id,
      content: TextContent(_mutate(block.content.plainText)),
      base: base == null ? null : ContentBase(version: base),
    );
  }

  SyncOp _move(int lamport, Block block, List<Block> blocks) {
    final siblings =
        blocks
            .where((candidate) => candidate.parent == block.parent)
            .map((candidate) => candidate.order)
            .toList()
          ..sort();
    final index = siblings.indexOf(block.order);
    final lower = index > 0 ? siblings[index - 1] : null;
    final upper = index >= 0 && index + 1 < siblings.length
        ? siblings[index + 1]
        : null;
    return MoveBlockOp(
      doc: _documentId,
      lamport: lamport,
      author: authorId,
      blockId: block.id,
      parent: block.parent,
      order: OrderKey.between(lower, upper),
    );
  }

  String _mutate(String text) {
    final choice = random.nextInt(4);
    if (text.isEmpty) return 'mot';
    final index = random.nextInt(text.length);
    return switch (choice) {
      0 => '$text-suite',
      1 => '${text.substring(0, index)}X${text.substring(index)}',
      2 => '${text.substring(0, index)}${text.substring(index + 1)}',
      _ => '$text-et',
    };
  }
}

void main() {
  group('CRDT conflict resolution', () {
    test('merges two concurrent edits of the same block', () {
      final document = CrdtDocument.empty(_documentId);
      const authorA = AuthorId('writer-a');
      const authorB = AuthorId('writer-b');
      const block = BlockId('block-1');

      final insert = InsertBlockOp(
        doc: _documentId,
        lamport: 1,
        author: authorA,
        blockId: block,
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Le chat dort'),
      );
      final editA = UpdateContentOp(
        doc: _documentId,
        lamport: 2,
        author: authorA,
        blockId: block,
        content: const TextContent('Le chat dort sur le tapis'),
        base: const ContentBase(
          version: VersionRef(lamport: 1, author: authorA),
        ),
      );
      final editB = UpdateContentOp(
        doc: _documentId,
        lamport: 2,
        author: authorB,
        blockId: block,
        content: const TextContent('Le chien dort'),
        base: const ContentBase(
          version: VersionRef(lamport: 1, author: authorA),
        ),
      );

      final merged = document.applyAll(<SyncOp>[insert, editA, editB]);
      final content = merged.blocks.single.content.plainText;
      expect(content, contains('tapis'));
      expect(content, contains('chien'));
    });

    test('lets the most recent deletion win over an older edit', () {
      final document = CrdtDocument.empty(_documentId);
      const authorA = AuthorId('writer-a');
      const block = BlockId('block-1');
      final insert = InsertBlockOp(
        doc: _documentId,
        lamport: 1,
        author: authorA,
        blockId: block,
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Texte'),
      );
      final deletion = DeleteBlockOp(
        doc: _documentId,
        lamport: 3,
        author: authorA,
        blockId: block,
      );
      final edit = UpdateContentOp(
        doc: _documentId,
        lamport: 2,
        author: authorA,
        blockId: block,
        content: const TextContent('Texte modifié'),
      );
      final deleted = document.applyAll(<SyncOp>[insert, edit, deletion]);
      expect(deleted.blocks.single.deleted, isTrue);
    });

    test(
      'resurrects a block when the edit is more recent than the deletion',
      () {
        final document = CrdtDocument.empty(_documentId);
        const authorA = AuthorId('writer-a');
        const block = BlockId('block-1');
        final insert = InsertBlockOp(
          doc: _documentId,
          lamport: 1,
          author: authorA,
          blockId: block,
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: const TextContent('Texte'),
        );
        final deletion = DeleteBlockOp(
          doc: _documentId,
          lamport: 2,
          author: authorA,
          blockId: block,
        );
        final edit = UpdateContentOp(
          doc: _documentId,
          lamport: 3,
          author: authorA,
          blockId: block,
          content: const TextContent('Texte relu'),
        );
        final alive = document.applyAll(<SyncOp>[insert, deletion, edit]);
        expect(alive.blocks.single.deleted, isFalse);
        expect(alive.blocks.single.content.plainText, 'Texte relu');
      },
    );

    test('is idempotent when the same operation is applied twice', () {
      final document = CrdtDocument.empty(_documentId);
      const authorA = AuthorId('writer-a');
      final insert = InsertBlockOp(
        doc: _documentId,
        lamport: 1,
        author: authorA,
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Texte'),
      );
      final once = document.apply(insert);
      final twice = once.apply(insert);
      expect(twice.blocks, once.blocks);
      expect(twice.operationCount, once.operationCount);
    });

    test('resolves concurrent metadata writes with the author tie-break', () {
      final document = CrdtDocument.empty(_documentId);
      final byA = SetMetaOp(
        doc: _documentId,
        lamport: 5,
        author: const AuthorId('writer-a'),
        key: 'title',
        value: 'A',
      );
      final byB = SetMetaOp(
        doc: _documentId,
        lamport: 5,
        author: const AuthorId('writer-b'),
        key: 'title',
        value: 'B',
      );
      expect(document.apply(byA).apply(byB).meta['title'], 'B');
      expect(document.apply(byB).apply(byA).meta['title'], 'B');
    });

    test('keeps concurrent marks without conflict', () {
      final document = CrdtDocument.empty(_documentId);
      const block = BlockId('block-1');
      final insert = InsertBlockOp(
        doc: _documentId,
        lamport: 1,
        author: const AuthorId('writer-a'),
        blockId: block,
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent('Texte'),
      );
      final markA = AddMarkOp(
        doc: _documentId,
        lamport: 2,
        author: const AuthorId('writer-a'),
        markId: const MarkId('mark-a'),
        blockId: block,
        type: MarkType.comment,
        range: MarkRange(start: 0, end: 2),
      );
      final markB = AddMarkOp(
        doc: _documentId,
        lamport: 2,
        author: const AuthorId('writer-b'),
        markId: const MarkId('mark-b'),
        blockId: block,
        type: MarkType.aiNote,
        range: MarkRange(start: 3, end: 5),
      );
      final merged = document.applyAll(<SyncOp>[insert, markA, markB]);
      expect(merged.blocks.single.marks, hasLength(2));
    });
  });

  group('CRDT convergence fuzz', () {
    for (var seed = 0; seed < _seedCount; seed++) {
      test('all agents converge with seed $seed', () {
        final random = math.Random(seed);
        final writers = <_Writer>[
          _Writer(const AuthorId('writer-a'), random),
          _Writer(const AuthorId('writer-b'), random),
        ];
        final relay = <SyncOp>[];

        for (var round = 0; round < _roundCount; round++) {
          for (final writer in writers) {
            final op = writer.produce();
            if (op == null) continue;
            writer.produced.add(op);
            relay.add(op);
          }
          // The relay reorders the operations and delivers them randomly:
          // duplicates are sent on purpose to exercise the idempotence. Only
          // a fraction of the pool is delivered so that concurrent edits pile
          // up before being reconciled.
          final shuffled = <SyncOp>[...relay]..shuffle(random);
          for (final writer in writers) {
            final limit = random.nextInt(shuffled.length + 1);
            for (final op in shuffled.take(limit)) {
              writer.receive(op);
            }
          }
        }

        // Final delivery: every agent receives every operation, in its own
        // random order.
        for (final writer in writers) {
          final shuffled = <SyncOp>[...relay]..shuffle(random);
          for (final op in shuffled) {
            writer.receive(op);
          }
        }

        final reference = writers.first.document;
        for (final writer in writers.skip(1)) {
          expect(
            writer.document.blocks,
            reference.blocks,
            reason: 'blocks differ for seed $seed',
          );
          expect(
            writer.document.meta,
            reference.meta,
            reason: 'metadata differ for seed $seed',
          );
        }

        // A fresh replica fed with the operations in another order must
        // reach the very same state.
        final fresh = CrdtDocument.empty(_documentId);
        final shuffled = <SyncOp>[...relay]..shuffle(random);
        final replay = shuffled.fold(fresh, (doc, op) => doc.apply(op));
        expect(replay.blocks, reference.blocks);
        expect(replay.meta, reference.meta);
      });
    }
  });
}
