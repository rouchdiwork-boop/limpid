import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

/// The document of the tests.
const DocumentId _documentId = DocumentId('document-ancres');

/// The author of the manuscript in the tests.
const AuthorId _author = AuthorId('auteur-a');

/// The block the comment is anchored on.
const BlockId _blockId = BlockId('block-1');

/// The mark of the discussion.
const MarkId _markId = MarkId('marque-1');

void main() {
  group('l’ancre suit le texte réécrit', () {
    test('une réécriture avant la plage décale la plage', () {
      final CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 6),
      );

      final CrdtDocument rewritten = _rewritten(
        document,
        'Oui, le sel vient des murs.',
      );

      expect(_rangeOf(rewritten), const MarkRange(start: 8, end: 11));
    });

    test('une réécriture après la plage ne la bouge pas', () {
      final CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 6),
      );

      final CrdtDocument rewritten = _rewritten(
        document,
        'Le sel vient des murs, enfin.',
      );

      expect(_rangeOf(rewritten), const MarkRange(start: 3, end: 6));
    });

    test('une réécriture au milieu de la plage la tronque', () {
      final CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 16),
      );

      final CrdtDocument rewritten = _rewritten(document, 'Le sel des murs.');

      expect(_rangeOf(rewritten), const MarkRange(start: 3, end: 10));
    });

    test('le texte commenté disparu vide la plage et garde la marque', () {
      final CrdtDocument document = _withComment(
        _withText('Sel'),
        const MarkRange(start: 0, end: 3),
      );

      final CrdtDocument rewritten = _rewritten(document, 'Pavé');

      expect(_rangeOf(rewritten), const MarkRange(start: 0, end: 0));
      expect(rewritten.blocks.first.marks.containsKey(_markId), isTrue);
    });

    test('une plage intacte reste la même', () {
      final CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 6),
      );

      expect(_rangeOf(document), const MarkRange(start: 3, end: 6));
    });

    test('la marque suit le texte à travers plusieurs réécritures', () {
      CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 6),
      );
      document = _rewritten(
        document,
        'Oui, le sel vient des murs.',
        lamport: 3,
      );
      document = _rewritten(document, 'Oui, le sel de la mer.', lamport: 4);

      expect(_rangeOf(document), const MarkRange(start: 8, end: 11));
    });
  });

  group('l’ancre ne bouge pas sans réécriture', () {
    test('le texte intact garde la plage', () {
      final CrdtDocument document = _withComment(
        _withText('Le sel vient des murs.'),
        const MarkRange(start: 3, end: 6),
      );

      expect(_rangeOf(document), const MarkRange(start: 3, end: 6));
      expect(document.blocks.first.content.plainText, 'Le sel vient des murs.');
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

/// The document, with a comment anchored on [range].
CrdtDocument _withComment(CrdtDocument document, MarkRange range) {
  return document.apply(
    AddMarkOp(
      doc: _documentId,
      lamport: 2,
      author: _author,
      markId: _markId,
      blockId: _blockId,
      type: MarkType.comment,
      range: range,
    ),
  );
}

/// The document, whose paragraph was rewritten.
CrdtDocument _rewritten(CrdtDocument document, String text, {int lamport = 3}) {
  return document.apply(
    UpdateContentOp(
      doc: _documentId,
      lamport: lamport,
      author: _author,
      blockId: _blockId,
      content: TextContent(text),
    ),
  );
}

/// The range of the comment in the document.
MarkRange _rangeOf(CrdtDocument document) {
  final MarkRange? range = document.blocks.first.marks[_markId];
  expect(range, isNotNull, reason: 'la marque doit rester présente');
  return range!;
}
