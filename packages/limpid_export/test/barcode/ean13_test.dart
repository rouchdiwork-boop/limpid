import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

/// La suite de modules du symbole, lisible comme une chaine.
String _pattern(Ean13 symbol) =>
    symbol.modules.map((bar) => bar ? '1' : '0').join();

void main() {
  group('Ean13', () {
    test('le symbole compte 95 modules', () {
      final symbol = Ean13.fromDigits('5901234123457');
      expect(symbol.modules.length, 95);
      expect(Ean13.moduleCount, 95);
    });

    test('les zones de silence entourent le symbole', () {
      expect(Ean13.leftQuietZone, 11);
      expect(Ean13.rightQuietZone, 7);
      expect(Ean13.totalWidth, 113);
    });

    test('les gardes sont places aux positions de la norme', () {
      final symbol = Ean13.fromDigits('5901234123457');

      expect(symbol.modules.sublist(0, 3), <bool>[true, false, true]);
      expect(symbol.modules.sublist(45, 50), <bool>[
        false,
        true,
        false,
        true,
        false,
      ]);
      expect(symbol.modules.sublist(92, 95), <bool>[true, false, true]);
    });

    test('le symbole encode exactement les modules attendus', () {
      final symbol = Ean13.fromDigits('5901234123457');

      expect(
        _pattern(symbol),
        '101'
        '0001011'
        '0100111'
        '0110011'
        '0010011'
        '0111101'
        '0011101'
        '01010'
        '1100110'
        '1101100'
        '1000010'
        '1011100'
        '1001110'
        '1000100'
        '101',
      );
    });

    test('la cle de controle est verifiee', () {
      expect(() => Ean13.fromDigits('5901234123458'), throwsFormatException);
      expect(() => Ean13.fromDigits('59012341234'), throwsFormatException);
      expect(() => Ean13.fromDigits('590123412345X'), throwsFormatException);
    });

    test('un ISBN invalide ne produit aucun symbole', () {
      expect(Ean13.tryParse('978-2-1234-5678-9'), isNull);
      expect(Ean13.tryParse(''), isNull);
      expect(Ean13.tryParse('pas un isbn'), isNull);
    });

    test('un ISBN valide produit le symbole de son ISBN-13', () {
      final symbol = Ean13.tryParse('9782123456780');
      expect(symbol, isNotNull);
      expect(symbol!.digits, '9782123456780');
    });

    test('un ISBN d edition imprimee garde son prefixe 979', () {
      final symbol = Ean13.tryParse('9792123456789');
      expect(symbol, isNotNull);
      expect(symbol!.digits, '9792123456789');
    });

    test('les suites de barres sont contigues et exhaustives', () {
      final symbol = Ean13.fromDigits('5901234123457');
      final runs = symbol.runs;

      expect(runs, isNotEmpty);
      var covered = 0;
      var previousEnd = -1;
      for (final run in runs) {
        expect(run.start, greaterThan(previousEnd));
        expect(run.length, greaterThan(0));
        covered += run.length;
        previousEnd = run.start + run.length - 1;
      }
      expect(
        covered,
        symbol.modules.where((bar) => bar).length,
        reason: 'Les suites de barres doivent couvrir toutes les barres.',
      );
    });

    test('le premier chiffre change la parite des chiffres de gauche', () {
      final even = Ean13.fromDigits('0901234123452');
      final odd = Ean13.fromDigits('1901234123451');

      expect(
        _pattern(even).substring(3, 45),
        isNot(_pattern(odd).substring(3, 45)),
        reason: 'La parite des chiffres de gauche depend du premier chiffre.',
      );
      expect(
        _pattern(even).substring(45, 50),
        _pattern(odd).substring(45, 50),
        reason: 'Le garde central ne depend pas du premier chiffre.',
      );
    });
  });
}
