import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import '../support/ops.dart';

/// La reconciliation d'un deplacement concurrent et d'une modification de
/// texte (D-04, critere 2.5).
///
/// Les deux operations touchent le meme bloc, mais deux choses differentes :
/// l'une deplace le bloc, l'autre reecrit son texte. Elles sont
/// **concurrentes** : chacune derive de la meme version, aucune ne voit
/// l'autre. Les regles de D-04 disent que la structure et le texte se
/// reconcilient separement, donc **le deplacement et le texte doivent
/// tous deux survivre**, et les deux clients doivent aboutir au meme etat.
void main() {
  group('deplacement concurrent et modification de texte', () {
    const doc = DocumentId('doc-move-concurrent');
    const blockId = BlockId('block-1');
    const otherBlockId = BlockId('block-2');

    test('le deplacement et le texte survivent tous les deux', () {
      final factoryA = OpFactory(const AuthorId('author-a'));
      final factoryB = OpFactory(const AuthorId('author-b'));

      // La base commune : le bloc, puis son voisin qui lui donne un ordre.
      final insert = factoryA.insertBlock(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Texte de base'),
        order: OrderKey.initial,
      );
      final neighbour = factoryA.insertBlock(
        doc: doc,
        blockId: otherBlockId,
        content: const TextContent('Le voisin'),
        order: OrderKey.between(OrderKey.initial, null),
      );
      factoryB.observe(insert);
      factoryB.observe(neighbour);
      final base = ContentBase(
        version: VersionRef(lamport: insert.lamport, author: insert.author),
      );

      // A deplace le bloc, B a reecrit son texte : les deux operations sont
      // concurrentes.
      final move = factoryA.moveBlock(
        doc: doc,
        blockId: blockId,
        order: OrderKey.between(OrderKey.initial, neighbourOrder(neighbour)),
      );
      final update = factoryB.updateContent(
        doc: doc,
        blockId: blockId,
        content: const TextContent('Texte reecrit'),
        base: base,
      );

      // Le client A recoit le texte de B, le client B recoit le
      // deplacement de A.
      final clientA = CrdtDocument.empty(
        doc,
      ).apply(insert).apply(neighbour).apply(move).apply(update);
      final clientB = CrdtDocument.empty(
        doc,
      ).apply(insert).apply(neighbour).apply(update).apply(move);

      expect(clientA.blocks, clientB.blocks);

      final Block block = clientA.blocks.firstWhere(
        (Block candidate) => candidate.id == blockId,
      );
      // Le texte reecrit n'est pas perdu...
      expect(block.content.plainText, 'Texte reecrit');
      // ...et le deplacement non plus.
      expect(block.order, move.order);
    });

    test(
      'un deplacement et une reecriture dans l autre ordre aboutissent au meme etat',
      () {
        final factoryA = OpFactory(const AuthorId('author-a'));
        final factoryB = OpFactory(const AuthorId('author-b'));

        final insert = factoryA.insertBlock(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Texte de base'),
        );
        final base = ContentBase(
          version: VersionRef(lamport: insert.lamport, author: insert.author),
        );
        final move = factoryA.moveBlock(
          doc: doc,
          blockId: blockId,
          order: OrderKey.between(OrderKey.initial, null),
        );
        final update = factoryB.updateContent(
          doc: doc,
          blockId: blockId,
          content: const TextContent('Texte reecrit'),
          base: base,
        );

        final dansLordre = CrdtDocument.empty(
          doc,
        ).apply(insert).apply(move).apply(update);
        final dansLordreInverse = CrdtDocument.empty(
          doc,
        ).apply(insert).apply(update).apply(move);

        expect(dansLordre.blocks, dansLordreInverse.blocks);
      },
    );
  });
}

/// L'ordre du bloc voisin, pour l'ecart qui suit le bloc deplace.
OrderKey neighbourOrder(InsertBlockOp operation) => operation.order;
