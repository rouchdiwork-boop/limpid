import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('OrderKey', () {
    test('compares keys lexicographically, not as floating point numbers', () {
      expect(OrderKey('1').compareTo(OrderKey('2')), isNegative);
      expect(OrderKey('95').compareTo(OrderKey('9')), isPositive);
      expect(OrderKey('5').compareTo(OrderKey('5')), isZero);
    });

    test('keeps the decimal order of the keys', () {
      // 0.025 < 0.05 < 0.5 : the lexicographic order matches the numeric one.
      expect(OrderKey('025').compareTo(OrderKey('05')), isNegative);
      expect(OrderKey('05').compareTo(OrderKey('5')), isNegative);
      expect(OrderKey('15').compareTo(OrderKey('105')), isPositive);
    });

    test('rejects a non canonical key', () {
      expect(() => OrderKey(''), throwsA(isA<InvalidSyncOperationException>()));
      expect(
        () => OrderKey('a'),
        throwsA(isA<InvalidSyncOperationException>()),
      );
      expect(
        () => OrderKey('10'),
        throwsA(isA<InvalidSyncOperationException>()),
        reason: 'a trailing zero would duplicate another key',
      );
    });

    test('accepts the zero sentinel', () {
      expect(OrderKey.zero.value, '0');
    });

    test('generates a key between two neighbours', () {
      final middle = OrderKey.between(OrderKey('5'), OrderKey('9'));
      expect(middle.compareTo(OrderKey('5')), isPositive);
      expect(middle.compareTo(OrderKey('9')), isNegative);
    });

    test('generates a key before the first neighbour', () {
      final first = OrderKey.between(null, OrderKey('5'));
      expect(first.compareTo(OrderKey.zero), isPositive);
      expect(first.compareTo(OrderKey('5')), isNegative);
    });

    test('generates a key after the last neighbour', () {
      final last = OrderKey.between(OrderKey('9'), null);
      expect(last.compareTo(OrderKey('9')), isPositive);
      expect(last, isNot(OrderKey('9')));
    });

    test('generates a key between two neighbours when there is no room', () {
      final middle = OrderKey.between(OrderKey('5'), OrderKey('55'));
      expect(middle.compareTo(OrderKey('5')), isPositive);
      expect(middle.compareTo(OrderKey('55')), isNegative);
    });

    test('keeps generating keys between two very close neighbours', () {
      final lower = OrderKey('5');
      var upper = OrderKey('9');
      for (var i = 0; i < 50; i++) {
        final middle = OrderKey.between(lower, upper);
        expect(middle.compareTo(lower), isPositive);
        expect(middle.compareTo(upper), isNegative);
        upper = middle;
      }
    });

    test('never generates the same key twice in a row', () {
      final keys = <OrderKey>[OrderKey.zero];
      for (var i = 0; i < 100; i++) {
        keys.add(OrderKey.between(keys.last, null));
      }
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('produces the same key for the same neighbours', () {
      expect(
        OrderKey.between(OrderKey('5'), OrderKey('9')),
        OrderKey.between(OrderKey('5'), OrderKey('9')),
      );
    });

    test('rejects neighbours that are not ordered', () {
      expect(
        () => OrderKey.between(OrderKey('9'), OrderKey('5')),
        throwsA(isA<InvalidSyncOperationException>()),
      );
      expect(
        () => OrderKey.between(OrderKey('5'), OrderKey('5')),
        throwsA(isA<InvalidSyncOperationException>()),
      );
    });

    test('supports equality and hashing', () {
      expect(OrderKey('5'), OrderKey('5'));
      expect(OrderKey('5').hashCode, OrderKey('5').hashCode);
      expect(OrderKey('5') == OrderKey('6'), isFalse);
    });

    test('keeps the semantic order of a list of keys', () {
      final keys = <OrderKey>[
        OrderKey('95'),
        OrderKey('5'),
        OrderKey('9'),
        OrderKey('25'),
      ]..sort();
      expect(keys.map((key) => key.value), <String>['25', '5', '9', '95']);
    });

    test('exposes before and after helpers', () {
      expect(OrderKey('5').isBefore(OrderKey('9')), isTrue);
      expect(OrderKey('9').isAfter(OrderKey('5')), isTrue);
      expect(OrderKey('5').isBefore(OrderKey('5')), isFalse);
    });
  });
}
