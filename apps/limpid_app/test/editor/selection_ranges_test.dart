import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/editor/selection_ranges.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// Bâtit un paragraphe de la scène.
SceneBlock blockOf(String id, String text) {
  return SceneBlock(
    id: BlockId(id),
    type: BlockType.paragraph,
    content: TextContent(text),
    order: OrderKey.initial,
  );
}

void main() {
  group('la plage de la sélection', () {
    final List<SceneBlock> blocks = <SceneBlock>[
      blockOf('bloc-1', 'Le sel qui vient des murs'),
      blockOf('bloc-2', 'Il recouvre les vitres'),
    ];

    test('relaie la sélection dans le bloc qui la porte', () {
      final SelectedPassage? passage = selectedPassageOf(
        blocks: blocks,
        start: 3,
        end: 10,
      );

      expect(passage, isNotNull);
      expect(passage!.blockId, const BlockId('bloc-1'));
      expect(passage.range, const MarkRange(start: 3, end: 10));
      expect(passage.text, 'sel qui');
    });

    test('compte la nouvelle ligne entre deux blocs', () {
      // Le second bloc commence après la nouvelle ligne du premier.
      final SelectedPassage? passage = selectedPassageOf(
        blocks: blocks,
        start: 26,
        end: 28,
      );

      expect(passage, isNotNull);
      expect(passage!.blockId, const BlockId('bloc-2'));
      expect(passage.range, const MarkRange(start: 0, end: 2));
      expect(passage.text, 'Il');
    });

    test('refuse une sélection qui traverse deux blocs', () {
      expect(selectedPassageOf(blocks: blocks, start: 3, end: 30), isNull);
    });

    test('refuse une sélection vide', () {
      expect(selectedPassageOf(blocks: blocks, start: 5, end: 5), isNull);
    });

    test('refuse une sélection qui prend la nouvelle ligne', () {
      expect(selectedPassageOf(blocks: blocks, start: 3, end: 26), isNull);
    });
  });
}
