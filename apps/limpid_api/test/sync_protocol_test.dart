import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('décodage des opérations', () {
    test('décode une insertion', () {
      final SyncOp op = SyncProtocol.decode(<String, dynamic>{
        'op_id': 'op-1',
        'doc_id': 'doc-1',
        'lamport': 4,
        'author_id': 'auteur-1',
        'type': 'insertBlock',
        'payload': <String, dynamic>{
          'block_id': 'block-1',
          'parent_id': null,
          'order_key': '5',
          'type': 'paragraph',
          'content': 'Texte.',
        },
        'schema_version': 1,
      });

      expect(op, isA<InsertBlockOp>());
      final InsertBlockOp insert = op as InsertBlockOp;
      expect(insert.doc.value, 'doc-1');
      expect(insert.lamport, 4);
      expect(insert.blockId.value, 'block-1');
      expect(insert.order.value, '5');
      expect(insert.content.plainText, 'Texte.');
    });

    test('décode une suppression', () {
      final SyncOp op = SyncProtocol.decode(<String, dynamic>{
        'op_id': 'op-2',
        'doc_id': 'doc-1',
        'lamport': 5,
        'author_id': 'auteur-1',
        'type': 'deleteBlock',
        'payload': <String, dynamic>{'block_id': 'block-1'},
        'schema_version': 1,
      });

      expect(op, isA<DeleteBlockOp>());
      expect((op as DeleteBlockOp).blockId.value, 'block-1');
    });

    test('refuse un type d\'opération inconnu', () {
      expect(
        () => SyncProtocol.decode(<String, dynamic>{
          'op_id': 'op-3',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'auteur-1',
          'type': 'operationInconnue',
          'payload': <String, dynamic>{},
          'schema_version': 1,
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('operationInconnue'),
          ),
        ),
      );
    });

    test('refuse une charge utile absente', () {
      expect(
        () => SyncProtocol.decode(<String, dynamic>{
          'op_id': 'op-4',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'auteur-1',
          'type': 'deleteBlock',
          'schema_version': 1,
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('payload'),
          ),
        ),
      );
    });

    test('refuse une clé de tri invalide', () {
      expect(
        () => SyncProtocol.decode(<String, dynamic>{
          'op_id': 'op-5',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'auteur-1',
          'type': 'insertBlock',
          'payload': <String, dynamic>{
            'block_id': 'block-1',
            'order_key': 'invalide',
            'type': 'paragraph',
            'content': 'Texte.',
          },
          'schema_version': 1,
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('order_key'),
          ),
        ),
      );
    });

    test('refuse une version de protocole en avance', () {
      expect(
        () => SyncProtocol.decode(<String, dynamic>{
          'op_id': 'op-6',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'auteur-1',
          'type': 'deleteBlock',
          'payload': <String, dynamic>{'block_id': 'block-1'},
          'schema_version': 99,
        }),
        throwsA(isA<ClientAheadException>()),
      );
    });

    test('encode une opération pour le réseau', () {
      final InsertBlockOp op = InsertBlockOp(
        doc: const DocumentId('doc-1'),
        lamport: 3,
        author: const AuthorId('auteur-1'),
        blockId: const BlockId('block-1'),
        parent: null,
        order: OrderKey('5'),
        type: BlockType.paragraph,
        content: const TextContent('Texte.'),
      );

      final Map<String, Object?> encoded = SyncProtocol.encode(op);

      expect(encoded['doc_id'], 'doc-1');
      expect(encoded['lamport'], 3);
      expect(encoded['type'], 'insertBlock');
      expect(
        (encoded['payload']! as Map<String, Object?>)['content'],
        'Texte.',
      );
    });
  });

  group('reconstruction de l\'arbre', () {
    test('reconstruit les blocs et leurs enfants', () {
      final List<SyncOpRecord> operations = <SyncOpRecord>[
        _record(1, 'block-1', null, '5', 'Titre'),
        _record(2, 'block-2', 'block-1', '7', 'Paragraphe'),
        _record(3, 'block-3', 'block-1', '9', 'Autre paragraphe'),
      ];

      final List<DocumentTree> trees = TreeBuilder.build(operations);

      expect(trees, hasLength(1));
      final DocumentTree tree = trees.first;
      expect(tree.docId, 'doc-1');
      expect(tree.lamport, 3);
      expect(tree.blocks, hasLength(1));
      expect(tree.blocks.first.id, 'block-1');
      expect(tree.blocks.first.children, hasLength(2));
      expect(tree.blocks.first.children.first.id, 'block-2');
    });

    test('ignore les opérations indécodables', () {
      final List<SyncOpRecord> operations = <SyncOpRecord>[
        _record(1, 'block-1', null, '5', 'Titre'),
        SyncOpRecord(
          opId: 'op-kasche',
          projectId: 'projet-1',
          docId: 'doc-1',
          lamport: 2,
          authorId: 'auteur-1',
          type: 'typeInconnu',
          payload: const <String, dynamic>{},
          schemaVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
      ];

      final List<DocumentTree> trees = TreeBuilder.build(operations);

      expect(trees.first.blocks, hasLength(1));
    });
  });
}

SyncOpRecord _record(
  int lamport,
  String blockId,
  String? parentId,
  String orderKey,
  String content,
) {
  return SyncOpRecord(
    opId: 'op-$lamport',
    projectId: 'projet-1',
    docId: 'doc-1',
    lamport: lamport,
    authorId: 'auteur-1',
    type: 'insertBlock',
    payload: <String, dynamic>{
      'block_id': blockId,
      'parent_id': parentId,
      'order_key': orderKey,
      'type': 'paragraph',
      'content': content,
    },
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );
}
