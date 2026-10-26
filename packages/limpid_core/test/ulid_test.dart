import 'dart:io';

import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

/// L'identifiant ULID et la source qui le produit.
void main() {
  group('UlidGenerator', () {
    test('produit des identifiants qui se trient par ordre de creation', () {
      final UlidGenerator generator = UlidGenerator();
      final Ulid premier = generator.generate();
      final Ulid second = generator.generate();

      expect(premier.value, isNotEmpty);
      expect(second.value.compareTo(premier.value), greaterThan(0));
    });

    test('la partie aleatoire occupe les quatre-vingt bits', () {
      // Un tirage replié a zero — ce que fait le compilateur du web avec
      // `1 << 32` — ne laisserait que les seize derniers bits. On verifie
      // donc que la partie haute bouge.
      final UlidGenerator generator = UlidGenerator();
      final Set<int> hauts = <int>{};
      for (int index = 0; index < 64; index++) {
        hauts.add((generator.generate().randomPart >> 48).toInt());
      }

      expect(hauts.length, greaterThan(1));
    });

    test('la source ne contient aucun decalage de 32 bits', () {
      // Le piege : sur le web, le compilateur replie la constante
      // `1 << 32` a zero, et le tirage devient `nextInt(0)`, qui leve une
      // `RangeError` au moment de creer un projet. Le poste de test, lui,
      // calcule `1 << 32` correctement : **le defaut ne se voit pas dans
      // les tests**. Ce garde-fou lit la source et refuse le decalage.
      final File source = File('lib/src/sync/ulid.dart');
      expect(
        source.existsSync(),
        isTrue,
        reason: 'la source du ULID est introuvable',
      );

      final String contenu = source.readAsStringSync();
      // Le commentaire qui explique le piege est tolere : on ne cherche
      // que les decalages reellement compiles.
      final String code = contenu
          .split('\n')
          .where((String ligne) => !ligne.trimLeft().startsWith('//'))
          .join('\n');

      expect(
        code.contains('<< 32') || code.contains('<<32'),
        isFalse,
        reason:
            'un decalage de 32 bits se replie a zero sur le web : ecris la '
            'borne en hexadecimal (0x100000000)',
      );
    });
  });
}
