import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/editor/editor_statistics.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_quill/limpid_quill.dart' show SceneBlock;

import 'fakes.dart';

void main() {
  test('the word counter counts the prose of the document', () {
    final CrdtDocument document = fakeDocument(
      documentId: 'document-1',
      text: 'Bonjour le monde',
    );

    expect(wordCountOf(document), 3);
  });

  test('the word counter ignores the deleted blocks', () {
    const DocumentId id = DocumentId('document-1');
    final CrdtDocument document =
        fakeDocument(documentId: 'document-1', text: 'Bonjour le monde').apply(
          const DeleteBlockOp(
            doc: id,
            lamport: 2,
            author: kFakeAuthor,
            blockId: BlockId('block-1'),
          ),
        );

    expect(wordCountOf(document), 0);
  });

  test('the reading time of an empty manuscript is zero', () {
    expect(readingMinutesOf(0), 0);
  });

  test('the reading time of a manuscript is at least one minute', () {
    expect(readingMinutesOf(3), 1);
    expect(readingMinutesOf(1000), 5);
  });

  test('the editor blocks keep the identifiers of the CRDT', () {
    final CrdtDocument document = fakeDocument(
      documentId: 'document-1',
      text: 'Bonjour le monde',
      blockId: 'block-42',
    );

    final List<SceneBlock> blocks = sceneBlocksOf(document);

    expect(blocks, hasLength(1));
    expect(blocks.single.id, const BlockId('block-42'));
    expect(blocks.single.type, BlockType.paragraph);
    expect(blocks.single.content.plainText, 'Bonjour le monde');
  });

  test('the Lamport timestamp of a document is the highest one it carries', () {
    final CrdtDocument document = fakeDocument(
      documentId: 'document-1',
      text: 'Bonjour le monde',
    );

    expect(lamportOf(document), 1);
  });
}
