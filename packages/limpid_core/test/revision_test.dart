import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

const DocumentId _documentId = DocumentId('document-revisions');
const AuthorId _author = AuthorId('author-a');

/// The revision of the operation `(lamport, author)`.
VersionRef _revision(int lamport) =>
    VersionRef(lamport: lamport, author: _author);

void main() {
  group('history of the versions', () {
    test(
      'the revisions of a document are its operations, the oldest first',
      () {
        final document = CrdtDocument.empty(_documentId)
            .apply(
              InsertBlockOp(
                doc: _documentId,
                lamport: 1,
                author: _author,
                blockId: const BlockId('block-1'),
                parent: null,
                order: OrderKey.initial,
                type: BlockType.paragraph,
                content: const TextContent('Premier.'),
              ),
            )
            .apply(
              UpdateContentOp(
                doc: _documentId,
                lamport: 2,
                author: _author,
                blockId: const BlockId('block-1'),
                content: const TextContent('Second.'),
              ),
            );

        final revisions = revisionsOf(document);

        expect(revisions.map((DocumentRevision r) => r.lamport), <int>[1, 2]);
        expect(revisions.first.blockCount, 1);
        expect(revisions.last.blockCount, 1);
      },
    );

    test('the comparison reports the blocks that were modified', () {
      final document = CrdtDocument.empty(_documentId)
          .apply(
            InsertBlockOp(
              doc: _documentId,
              lamport: 1,
              author: _author,
              blockId: const BlockId('block-1'),
              parent: null,
              order: OrderKey.initial,
              type: BlockType.paragraph,
              content: const TextContent('Premier.'),
            ),
          )
          .apply(
            UpdateContentOp(
              doc: _documentId,
              lamport: 2,
              author: _author,
              blockId: const BlockId('block-1'),
              content: const TextContent('Second.'),
            ),
          );

      final comparison = compareDocumentRevisions(
        document,
        from: _revision(1),
        to: _revision(2),
      );

      expect(comparison.changes, hasLength(1));
      expect(comparison.modifiedCount, 1);
      final BlockChange change = comparison.changes.single;
      expect(change.kind, BlockChangeKind.modified);
      expect(change.blockId, const BlockId('block-1'));
      expect(change.beforeText, 'Premier.');
      expect(change.afterText, 'Second.');
    });

    test('the comparison reports the blocks that were added', () {
      final document = CrdtDocument.empty(_documentId).apply(
        InsertBlockOp(
          doc: _documentId,
          lamport: 1,
          author: _author,
          blockId: const BlockId('block-1'),
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: const TextContent('Premier.'),
        ),
      );

      final comparison = compareDocumentRevisions(
        document,
        from: originRevision,
        to: _revision(1),
      );

      expect(comparison.changes, hasLength(1));
      expect(comparison.addedCount, 1);
      expect(comparison.changes.single.kind, BlockChangeKind.added);
      expect(comparison.changes.single.afterText, 'Premier.');
    });

    test('the comparison reports the blocks that were removed', () {
      final document = CrdtDocument.empty(_documentId)
          .apply(
            InsertBlockOp(
              doc: _documentId,
              lamport: 1,
              author: _author,
              blockId: const BlockId('block-1'),
              parent: null,
              order: OrderKey.initial,
              type: BlockType.paragraph,
              content: const TextContent('Premier.'),
            ),
          )
          .apply(
            DeleteBlockOp(
              doc: _documentId,
              lamport: 2,
              author: _author,
              blockId: const BlockId('block-1'),
            ),
          );

      final comparison = compareDocumentRevisions(
        document,
        from: _revision(1),
        to: _revision(2),
      );

      expect(comparison.changes, hasLength(1));
      expect(comparison.removedCount, 1);
      expect(comparison.changes.single.kind, BlockChangeKind.removed);
    });

    test('a moved block is reported as moved, with its old and new order', () {
      final document = CrdtDocument.empty(_documentId)
          .apply(
            InsertBlockOp(
              doc: _documentId,
              lamport: 1,
              author: _author,
              blockId: const BlockId('block-1'),
              parent: null,
              order: OrderKey('5'),
              type: BlockType.paragraph,
              content: const TextContent('Premier.'),
            ),
          )
          .apply(
            InsertBlockOp(
              doc: _documentId,
              lamport: 2,
              author: _author,
              blockId: const BlockId('block-2'),
              parent: null,
              order: OrderKey('7'),
              type: BlockType.paragraph,
              content: const TextContent('Second.'),
            ),
          )
          .apply(
            MoveBlockOp(
              doc: _documentId,
              lamport: 3,
              author: _author,
              blockId: const BlockId('block-2'),
              parent: null,
              order: OrderKey('3'),
            ),
          );

      final comparison = compareDocumentRevisions(
        document,
        from: _revision(2),
        to: _revision(3),
      );

      expect(comparison.changes, hasLength(1));
      expect(comparison.movedCount, 1);
      final BlockChange change = comparison.changes.single;
      expect(change.kind, BlockChangeKind.moved);
      expect(change.before!.order.value, '7');
      expect(change.after!.order.value, '3');
    });

    test('two identical revisions hold the same document', () {
      final document = CrdtDocument.empty(_documentId).apply(
        InsertBlockOp(
          doc: _documentId,
          lamport: 1,
          author: _author,
          blockId: const BlockId('block-1'),
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: const TextContent('Premier.'),
        ),
      );

      final comparison = compareDocumentRevisions(
        document,
        from: _revision(1),
        to: _revision(1),
      );

      expect(comparison.isEmpty, isTrue);
      expect(comparison.changedBlockCount, 0);
    });

    test(
      'the comparison never compares two texts but two states of blocks',
      () {
        final document = CrdtDocument.empty(_documentId)
            .apply(
              InsertBlockOp(
                doc: _documentId,
                lamport: 1,
                author: _author,
                blockId: const BlockId('block-1'),
                parent: null,
                order: OrderKey.initial,
                type: BlockType.paragraph,
                content: const TextContent('Premier.'),
              ),
            )
            .apply(
              InsertBlockOp(
                doc: _documentId,
                lamport: 2,
                author: _author,
                blockId: const BlockId('block-2'),
                parent: null,
                order: OrderKey('7'),
                type: BlockType.paragraph,
                content: const TextContent('Second.'),
              ),
            );

        final comparison = compareDocumentRevisions(
          document,
          from: _revision(1),
          to: _revision(2),
        );

        // Le second bloc est signale, le premier ne l'est pas : la
        // comparaison porte sur les etats des blocs, pas sur les textes.
        expect(comparison.changes, hasLength(1));
        expect(comparison.changes.single.blockId, const BlockId('block-2'));
      },
    );
  });
}
