import 'dart:convert';

import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

const DocumentId _documentId = DocumentId('document-state');
const AuthorId _author = AuthorId('author-a');

void main() {
  group('compacted state of a document', () {
    final CrdtDocument document = CrdtDocument.empty(_documentId)
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
        )
        .apply(
          SetMetaOp(
            doc: _documentId,
            lamport: 3,
            author: _author,
            key: 'title',
            value: 'Le titre',
          ),
        )
        .apply(
          DeleteBlockOp(
            doc: _documentId,
            lamport: 4,
            author: _author,
            blockId: const BlockId('block-2'),
          ),
        );

    test('the state rebuilds a document that holds the same blocks', () {
      final state = CrdtState.fromDocument(document);

      final rebuilt = state.toDocument();

      expect(rebuilt.blocks, equals(document.blocks));
      expect(rebuilt.meta, equals(document.meta));
      expect(rebuilt.operationCount, document.operationCount);
      expect(rebuilt.appliedKeys, equals(document.appliedKeys));
    });

    test('the state survives a JSON round trip', () {
      final state = CrdtState.fromDocument(document);

      final decoded = CrdtState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
        documentId: _documentId,
      );

      expect(decoded.blocks.keys, equals(state.blocks.keys));
      expect(
        decoded.meta.map(
          (String key, MetaEntry entry) => MapEntry(key, entry.value),
        ),
        equals(
          state.meta.map(
            (String key, MetaEntry entry) => MapEntry(key, entry.value),
          ),
        ),
      );
      expect(decoded.appliedKeys, equals(state.appliedKeys));
      expect(decoded.toDocument().blocks, equals(document.blocks));
    });

    test('the state keeps the memory of the applied operations', () {
      final state = CrdtState.fromDocument(document);

      expect(state.appliedKeys, hasLength(4));
      for (final String key in state.appliedKeys) {
        expect(key, startsWith('${_documentId.value}/'));
      }
    });

    test('a malformed state is refused', () {
      expect(
        () => CrdtState.fromJson(<String, Object?>{
          'blocks': 'not a map',
        }, documentId: _documentId),
        throwsA(isA<InvalidDocumentException>()),
      );
    });
  });
}
