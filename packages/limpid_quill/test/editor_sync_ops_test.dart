import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_quill/limpid_quill.dart';

const DocumentId _document = DocumentId('document-1');
const AuthorId _author = AuthorId('auteur-1');

SceneBlock _block(int index, BlockType type, String text) {
  return SceneBlock(
    id: BlockId('bloc-$index'),
    type: type,
    content: deltaToBlockContent(Delta()..insert(text)),
    order: generateSceneOrders(index + 1).last,
  );
}

void main() {
  group('Conversion d’une opération d’éditeur', () {
    test('un texte saisi met à jour le bloc de la ligne', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
      ];
      final Delta before = Delta()..insert('Bonjour\n');
      final Delta change = Delta()
        ..retain(7)
        ..insert('!')
        ..retain(1);

      final List<SyncOp> ops = changeToSyncOps(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: before,
        change: change,
      );

      expect(ops, hasLength(1));
      expect(ops.single, isA<UpdateContentOp>());
      final UpdateContentOp op = ops.single as UpdateContentOp;
      expect(op.blockId, blocks.first.id);
      expect(op.content.plainText, 'Bonjour!');
    });

    test('un saut de ligne insère un bloc', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
      ];
      final Delta before = Delta()..insert('Bonjour\n');
      final Delta change = Delta()
        ..retain(7)
        ..insert('\n')
        ..retain(1);

      final SceneChange change1 = convertLocalChange(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: before,
        change: change,
      );

      expect(change1.ops, hasLength(1));
      expect(change1.ops.single, isA<InsertBlockOp>());
      expect(change1.state.blocks, hasLength(2));
      expect(change1.state.blocks[1].order.isAfter(blocks.first.order), isTrue);
    });

    test('une suppression de saut de ligne fusionne deux blocs', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
        _block(1, BlockType.paragraph, 'Le monde'),
      ];
      final Delta before = Delta()..insert('Bonjour\nLe monde\n');
      final Delta change = Delta()
        ..retain(7)
        ..delete(1)
        ..retain(9);

      final List<SyncOp> ops = changeToSyncOps(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: before,
        change: change,
      );

      expect(ops, hasLength(2));
      expect(ops[0], isA<UpdateContentOp>());
      expect((ops[0] as UpdateContentOp).content.plainText, 'BonjourLe monde');
      expect(ops[1], isA<DeleteBlockOp>());
      expect((ops[1] as DeleteBlockOp).blockId, blocks[1].id);
    });

    test('un changement vide ne produit aucune opération', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
      ];

      final List<SyncOp> ops = changeToSyncOps(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: Delta()..insert('Bonjour\n'),
        change: Delta(),
      );

      expect(ops, isEmpty);
    });
  });

  group('Application d’une opération distante', () {
    test('une mise à jour de contenu donne le même état', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
      ];
      final Delta before = Delta()..insert('Bonjour\n');
      final Delta change = Delta()
        ..retain(7)
        ..insert('!')
        ..retain(1);

      final SceneChange local = convertLocalChange(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: before,
        change: change,
      );

      SceneEditorState remote = SceneEditorState(
        document: before,
        blocks: blocks,
      );
      for (final SyncOp op in local.ops) {
        remote = applyRemoteOp(state: remote, op: op);
      }

      expect(remote.document, local.state.document);
      expect(remote.blocks, local.state.blocks);
    });

    test('une insertion de bloc donne le même état', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Bonjour'),
      ];
      final Delta before = Delta()..insert('Bonjour\n');
      final Delta change = Delta()
        ..retain(7)
        ..insert('\n')
        ..retain(1);

      final SceneChange local = convertLocalChange(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        before: before,
        change: change,
      );

      SceneEditorState remote = SceneEditorState(
        document: before,
        blocks: blocks,
      );
      for (final SyncOp op in local.ops) {
        remote = applyRemoteOp(state: remote, op: op);
      }

      expect(remote.blocks, hasLength(2));
      expect(remote.document, local.state.document);
    });

    test('un déplacement de bloc réordonne les blocs', () {
      final List<SceneBlock> blocks = <SceneBlock>[
        _block(0, BlockType.paragraph, 'Un'),
        _block(1, BlockType.paragraph, 'Deux'),
        _block(2, BlockType.paragraph, 'Trois'),
      ];
      final SceneEditorState state = SceneEditorState(
        document: sceneBlocksToDelta(blocks),
        blocks: blocks,
      );
      final MoveBlockOp move = MoveBlockOp(
        doc: _document,
        lamport: 1,
        author: _author,
        blockId: blocks[2].id,
        parent: null,
        order: OrderKey.between(blocks[0].order, blocks[1].order),
      );

      final SceneEditorState moved = applyRemoteOp(state: state, op: move);

      expect(moved.blocks[1].id, blocks[2].id);
      expect(moved.blocks[2].id, blocks[1].id);
    });
  });
}
