import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

void main() {
  group('OpCodec', () {
    const doc = DocumentId('doc-codec');
    const author = AuthorId('author-a');

    test('every kind of operation survives a round trip', () {
      final operations = <SyncOp>[
        InsertBlockOp(
          doc: doc,
          lamport: 1,
          author: author,
          blockId: const BlockId('block-1'),
          parent: const BlockId('block-0'),
          order: OrderKey.initial,
          type: BlockType.heading2,
          content: const TextContent('Un titre'),
        ),
        DeleteBlockOp(
          doc: doc,
          lamport: 2,
          author: author,
          blockId: const BlockId('block-1'),
        ),
        UpdateContentOp(
          doc: doc,
          lamport: 3,
          author: author,
          blockId: const BlockId('block-1'),
          content: const InlineContent(
            deltaJson: '{"ops":[{"insert":"Il pleuvait."}]}',
            plainText: 'Il pleuvait.',
          ),
          base: const ContentBase(
            version: VersionRef(lamport: 2, author: author),
          ),
        ),
        MoveBlockOp(
          doc: doc,
          lamport: 4,
          author: author,
          blockId: const BlockId('block-1'),
          parent: null,
          order: OrderKey('75'),
        ),
        SetMetaOp(
          doc: doc,
          lamport: 5,
          author: author,
          key: 'title',
          value: 'Les Heures de Cendre',
        ),
        AddMarkOp(
          doc: doc,
          lamport: 6,
          author: author,
          markId: const MarkId('mark-1'),
          blockId: const BlockId('block-1'),
          type: MarkType.comment,
          range: const MarkRange(start: 0, end: 4),
          body: 'À revoir.',
        ),
        RemoveMarkOp(
          doc: doc,
          lamport: 7,
          author: author,
          markId: const MarkId('mark-1'),
          blockId: const BlockId('block-1'),
        ),
      ];

      for (final operation in operations) {
        final encoded = OpCodec.encode(operation);
        expect(encoded['doc_id'], doc.value);
        expect(encoded['lamport'], operation.lamport);
        expect(encoded['author_id'], author.value);
        expect(encoded['schema_version'], syncProtocolSchemaVersion);
        expect(OpCodec.decode(encoded), operation);
      }
    });

    test('a malformed payload raises a transport error', () {
      expect(
        () => OpCodec.decode(<String, Object?>{'doc_id': 'doc'}),
        throwsA(isA<SyncTransportException>()),
      );
      expect(
        () => OpCodec.decode(<String, Object?>{
          'doc_id': 'doc',
          'lamport': 1,
          'author_id': 'author',
          'type': 'unknown',
          'payload': <String, Object?>{},
        }),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('the operation key is the identity of the operation', () {
      final operation = InsertBlockOp(
        doc: doc,
        lamport: 12,
        author: author,
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey.initial,
        type: BlockType.paragraph,
        content: const TextContent(''),
      );

      expect(operation.operationKey, 'doc-codec/12/author-a');
      expect(OpCodec.encode(operation)['op_id'], operation.operationKey);
    });
  });
}
