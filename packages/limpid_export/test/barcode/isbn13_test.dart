import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

void main() {
  group('Isbn13', () {
    test('les tirets et les espaces sont retires', () {
      expect(Isbn13.normalize('978-2-1234-5678-0'), '9782123456780');
      expect(Isbn13.normalize('978 2 1234 5678 0'), '9782123456780');
      expect(Isbn13.normalize(' 9782123456780 '), '9782123456780');
    });

    test('la cle de controle d un EAN-13 est calculee', () {
      expect(Isbn13.checkDigitOf('978212345678'), '0');
      expect(Isbn13.checkDigitOf('979212345678'), '9');
      expect(Isbn13.checkDigitOf('590123412345'), '7');
      expect(Isbn13.checkDigitOf('000000000000'), '0');
    });

    test('un ISBN-13 valide est accepte tel quel', () {
      final isbn = Isbn13.tryParse('9782123456780');
      expect(isbn, isNotNull);
      expect(isbn!.digits, '9782123456780');
    });

    test('le prefixe n est pas remplace : le code porte le numero saisi', () {
      // L'edition imprimee porte son propre ISBN, dans la plage 979 :
      // ce nombre est attribue, il n'est pas derive. Le fabriquer
      // produirait un code qui ne correspond a aucun livre enregistre.
      final isbn = Isbn13.tryParse('978-2-1234-5678-0');
      expect(isbn, isNotNull);
      expect(isbn!.digits, '9782123456780');
      expect(isbn.digits.length, 13);
    });

    test('un ISBN-13 deja en 979 est conserve', () {
      final isbn = Isbn13.tryParse('9792123456789');
      expect(isbn, isNotNull);
      expect(isbn!.digits, '9792123456789');
    });

    test('un ISBN-13 dont la cle est fausse est refuse', () {
      expect(Isbn13.tryParse('9782123456789'), isNull);
      expect(Isbn13.tryParse('978-2-1234-5678-9'), isNull);
      expect(Isbn13.isValid('978-2-1234-5678-9'), isFalse);
    });

    test('un ISBN-10 valide est converti dans la plage 978', () {
      final isbn = Isbn13.tryParse('0-306-40615-2');
      expect(isbn, isNotNull);
      expect(isbn!.digits, '9780306406157');
    });

    test('un ISBN-10 dont la cle est X est accepte', () {
      final isbn = Isbn13.tryParse('043942089X');
      expect(isbn, isNotNull);
      expect(isbn!.digits, '9780439420891');
    });

    test('un ISBN-10 dont la cle est fausse est refuse', () {
      expect(Isbn13.tryParse('0306406153'), isNull);
      expect(Isbn13.tryParse('2123456789'), isNull);
    });

    test('un ISBN mal forme est refuse', () {
      expect(Isbn13.tryParse(''), isNull);
      expect(Isbn13.tryParse('123'), isNull);
      expect(Isbn13.tryParse('978212345678X'), isNull);
      expect(Isbn13.tryParse('abcdefghijklm'), isNull);
    });

    test('le livre n est jamais modifie', () {
      final isbn = Isbn13.tryParse('9782123456780');
      expect(isbn!.digits, '9782123456780');
      expect(isbn.digits, '9782123456780');
    });
  });
}
