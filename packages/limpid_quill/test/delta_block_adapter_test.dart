import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_quill/limpid_quill.dart';

void main() {
  group('Delta et BlockContent', () {
    test('un delta simple fait un aller-retour exact', () {
      final Delta delta = Delta()..insert('Bonjour');

      final BlockContent content = deltaToBlockContent(delta);

      expect(content, isA<InlineContent>());
      expect((content as InlineContent).plainText, 'Bonjour');
      expect(blockContentToDelta(content), delta);
    });

    test('un delta enrichi fait un aller-retour exact', () {
      final Delta delta = Delta()
        ..insert('Bonjour', <String, dynamic>{'bold': true})
        ..insert(' le monde');

      final BlockContent content = deltaToBlockContent(delta);

      expect((content as InlineContent).plainText, 'Bonjour le monde');
      expect(blockContentToDelta(content), delta);
    });

    test('un objet intégré fait un aller-retour exact', () {
      final Delta delta = Delta()
        ..insert(<String, dynamic>{'image': 'https://exemple.test/a.png'});

      final BlockContent content = deltaToBlockContent(delta);

      expect(blockContentToDelta(content), delta);
    });

    test('un contenu simple redevient un delta', () {
      expect(
        blockContentToDelta(const TextContent('Bonjour')),
        Delta()..insert('Bonjour'),
      );
    });

    test('un contenu riche invalide est refusé', () {
      expect(
        () => blockContentToDelta(
          const InlineContent(deltaJson: 'pas un delta', plainText: ''),
        ),
        throwsFormatException,
      );
    });
  });

  group('Blocs de scène', () {
    test('un document fait un aller-retour exact à travers les blocs', () {
      final Delta delta = Delta()
        ..insert('Bonjour\n')
        ..insert('Le monde', <String, dynamic>{'bold': true})
        ..insert('\n', <String, dynamic>{'header': 1});

      final List<SceneBlock> blocks = deltaToSceneBlocks(
        delta,
        blockIdAt: (int index) => BlockId('bloc-$index'),
        orderAt: (int index) => generateSceneOrders(index + 1).last,
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].type, BlockType.paragraph);
      expect(blocks[1].type, BlockType.heading1);
      expect(sceneBlocksToDelta(blocks), delta);
    });

    test('les types de blocs sont reconnus', () {
      final Map<String, dynamic> heading = <String, dynamic>{'header': 2};
      final Map<String, dynamic> list = <String, dynamic>{'list': 'bullet'};
      final Map<String, dynamic> quote = <String, dynamic>{'blockquote': true};
      final Map<String, dynamic> code = <String, dynamic>{'code-block': true};

      expect(blockTypeOf(null), BlockType.paragraph);
      expect(blockTypeOf(heading), BlockType.heading2);
      expect(blockTypeOf(list), BlockType.listItem);
      expect(blockTypeOf(quote), BlockType.quote);
      expect(blockTypeOf(code), BlockType.code);
      expect(
        blockTypeOf(<String, dynamic>{kSceneBreakAttribute: true}),
        BlockType.sceneBreak,
      );
      expect(
        blockTypeOf(<String, dynamic>{kFootnoteAttribute: true}),
        BlockType.footnote,
      );
    });

    test('les attributs de bloc font l’aller-retour', () {
      // The image is not carried by an attribute but by an embedded object,
      // so it is detected from the content of the line.
      for (final BlockType type in BlockType.values) {
        if (type == BlockType.image) {
          continue;
        }
        expect(blockTypeOf(blockAttributesOf(type)), type);
      }
    });

    test('une image devient un bloc image', () {
      final Delta delta = Delta()
        ..insert(<String, dynamic>{'image': 'https://exemple.test/a.png'})
        ..insert('\n');

      final List<SceneBlock> blocks = deltaToSceneBlocks(
        delta,
        blockIdAt: (int index) => BlockId('bloc-$index'),
        orderAt: (int index) => generateSceneOrders(index + 1).last,
      );

      expect(blocks, hasLength(1));
      expect(blocks.first.type, BlockType.image);
      expect(sceneBlocksToDelta(blocks), delta);
    });

    test('la séparation de scène survit au voyage', () {
      final Delta delta = Delta()
        ..insert('Avant\n')
        ..insert('\n', <String, dynamic>{kSceneBreakAttribute: true})
        ..insert('Après\n');

      final List<SceneBlock> blocks = deltaToSceneBlocks(
        delta,
        blockIdAt: (int index) => BlockId('bloc-$index'),
        orderAt: (int index) => generateSceneOrders(index + 1).last,
      );

      expect(blocks, hasLength(3));
      expect(blocks[1].type, BlockType.sceneBreak);
      expect(sceneBlocksToDelta(blocks), delta);
    });

    test('les indices fractionnaires sont croissants', () {
      final List<OrderKey> orders = generateSceneOrders(4);

      expect(orders, hasLength(4));
      for (int i = 1; i < orders.length; i++) {
        expect(orders[i].isAfter(orders[i - 1]), isTrue);
      }
    });
  });
}
