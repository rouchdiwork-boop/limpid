import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/features/revision/revision_anchors.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_core/limpid_core.dart';

/// The document of the tests.
const DocumentId _documentId = DocumentId('document-ancres');

/// The author of the manuscript in the tests.
const AuthorId _author = AuthorId('auteur-a');

/// The block the comment is anchored on.
const BlockId _blockId = BlockId('block-1');

/// The mark of the discussion.
const MarkId _markId = MarkId('marque-1');

/// The discussion anchored on the mark.
CommentThread get _thread => CommentThread(
  id: const CommentId('fil-1'),
  markId: _markId,
  comments: <Comment>[
    Comment(
      id: const CommentId('message-1'),
      threadId: const CommentId('fil-1'),
      author: _author,
      body: 'Le sel vient des murs.',
      createdAt: DateTime.utc(2026, 10, 26),
    ),
  ],
);

void main() {
  group('les ancres des discussions', () {
    test('l’ancre suit le texte réécrit', () {
      final CrdtDocument document = _rewritten(
        _withComment(_withText('Le sel vient des murs.')),
        'Oui, le sel vient des murs.',
      );

      final List<RevisionAnchor> anchors = revisionAnchorsOf(
        document: document,
        threads: <CommentThread>[_thread],
      );

      expect(anchors, hasLength(1));
      expect(anchors.single.range, const MarkRange(start: 8, end: 11));
      expect(anchors.single.excerpt, 'sel');
    });

    test('la discussion ne se perd pas quand le texte commenté disparaît', () {
      final CrdtDocument document = _rewritten(
        _withComment(_withText('Le sel vient des murs.')),
        'Du sable.',
      );

      final List<RevisionAnchor> anchors = revisionAnchorsOf(
        document: document,
        threads: <CommentThread>[_thread],
      );

      expect(anchors, hasLength(1));
      expect(anchors.single.thread.id, const CommentId('fil-1'));
      expect(anchors.single.range.start, lessThanOrEqualTo(9));
      expect(anchors.single.range.end, lessThanOrEqualTo(9));
    });

    test('une discussion sans ancre ne mène à rien', () {
      final CrdtDocument document = _withText('Le sel vient des murs.');

      final List<RevisionAnchor> anchors = revisionAnchorsOf(
        document: document,
        threads: <CommentThread>[_thread],
      );

      expect(anchors, isEmpty);
    });
  });
}

/// A document holding one paragraph.
CrdtDocument _withText(String text) {
  return CrdtDocument.empty(_documentId).apply(
    InsertBlockOp(
      doc: _documentId,
      lamport: 1,
      author: _author,
      blockId: _blockId,
      parent: null,
      order: OrderKey.initial,
      type: BlockType.paragraph,
      content: TextContent(text),
    ),
  );
}

/// The document, with a comment anchored on the words of the salt.
CrdtDocument _withComment(CrdtDocument document) {
  return document.apply(
    const AddMarkOp(
      doc: _documentId,
      lamport: 2,
      author: _author,
      markId: _markId,
      blockId: _blockId,
      type: MarkType.comment,
      range: MarkRange(start: 3, end: 6),
    ),
  );
}

/// The document, whose paragraph was rewritten.
CrdtDocument _rewritten(CrdtDocument document, String text) {
  return document.apply(
    UpdateContentOp(
      doc: _documentId,
      lamport: 3,
      author: _author,
      blockId: _blockId,
      content: TextContent(text),
    ),
  );
}
