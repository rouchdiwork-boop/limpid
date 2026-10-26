import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import 'test_helpers.dart';

const DocumentId _document = DocumentId('document-1');
const AuthorId _author = AuthorId('auteur-1');

List<LimpidDraggableBlock> _blocks() {
  return <LimpidDraggableBlock>[
    LimpidDraggableBlock(id: const BlockId('a'), order: OrderKey('5')),
    LimpidDraggableBlock(id: const BlockId('b'), order: OrderKey('75')),
    LimpidDraggableBlock(id: const BlockId('c'), order: OrderKey('875')),
  ];
}

void main() {
  group('Déplacement d’un bloc', () {
    test('le glissement produit une opération moveBlock', () {
      final MoveBlockOp move = computeBlockMove(
        doc: _document,
        author: _author,
        lamport: 7,
        blocks: _blocks(),
        blockId: const BlockId('c'),
        targetIndex: 1,
      );

      expect(move, isA<MoveBlockOp>());
      expect(move.kind, 'moveBlock');
      expect(move.blockId, const BlockId('c'));
      expect(move.doc, _document);
      expect(move.author, _author);
      expect(move.lamport, 7);
    });

    test('le nouvel indice est strictement entre les voisins', () {
      final List<LimpidDraggableBlock> blocks = _blocks();

      final MoveBlockOp move = computeBlockMove(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        blockId: const BlockId('c'),
        targetIndex: 1,
      );

      expect(move.order.isAfter(blocks[0].order), isTrue);
      expect(move.order.isBefore(blocks[1].order), isTrue);
    });

    test('le premier voisin devient la borne inférieure', () {
      final List<LimpidDraggableBlock> blocks = _blocks();

      final MoveBlockOp move = computeBlockMove(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        blockId: const BlockId('c'),
        targetIndex: 0,
      );

      expect(move.order.isBefore(blocks[0].order), isTrue);
    });

    test('le dernier voisin devient la borne supérieure', () {
      final List<LimpidDraggableBlock> blocks = _blocks();

      final MoveBlockOp move = computeBlockMove(
        doc: _document,
        author: _author,
        lamport: 1,
        blocks: blocks,
        blockId: const BlockId('a'),
        targetIndex: 2,
      );

      expect(move.order.isAfter(blocks[1].order), isTrue);
    });

    test('un bloc inconnu est refusé', () {
      expect(
        () => computeBlockMove(
          doc: _document,
          author: _author,
          lamport: 1,
          blocks: _blocks(),
          blockId: const BlockId('inconnu'),
          targetIndex: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Poignée de glissement', () {
    testWidgets('elle mesure 24 × 24 pixels', (tester) async {
      await tester.pumpWidget(
        limpidTestApp(
          child: const Center(child: LimpidDragHandle(onDragStart: null)),
        ),
      );
      await tester.pump();

      final Size size = tester.getSize(find.byType(LimpidDragHandle));

      expect(size.width, kDragHandleSize);
      expect(size.height, kDragHandleSize);
    });

    testWidgets('elle apparaît au survol', (tester) async {
      await tester.pumpWidget(
        limpidTestApp(
          child: const Center(child: LimpidDragHandle(onDragStart: null)),
        ),
      );
      await tester.pump();

      AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0);

      final TestGesture gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(
        location: tester.getCenter(find.byType(LimpidDragHandle)),
      );
      await tester.pump();

      opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1);
    });

    testWidgets('elle porte les couleurs du thème', (tester) async {
      await tester.pumpWidget(
        limpidTestApp(
          child: const Center(child: LimpidDragHandle(onDragStart: null)),
        ),
      );
      await tester.pump();

      final Material material = tester.widget<Material>(
        find.descendant(
          of: find.byType(LimpidDragHandle),
          matching: find.byType(Material),
        ),
      );
      final RoundedRectangleBorder shape =
          material.shape! as RoundedRectangleBorder;
      final BorderSide side = shape.side;

      expect(material.color, LimpidColors.paper.bgRaised);
      expect(side.color, LimpidColors.paper.borderDefault);
    });
  });
}
