import 'dart:math' as math;

import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('LamportClock', () {
    test('starts at zero', () {
      expect(const LamportClock().current, 0);
    });

    test('advances by one tick', () {
      const clock = LamportClock();
      expect(clock.tick().current, 1);
      expect(clock.tick().tick().current, 2);
    });

    test('does not mutate the original clock', () {
      const clock = LamportClock();
      clock.tick();
      expect(clock.current, 0);
    });

    test('is strictly newer than a remote event when receiving it', () {
      const clock = LamportClock(5);
      expect(clock.receive(9).current, 10);
      expect(clock.receive(2).current, 6);
    });

    test('observes a remote event without generating a local one', () {
      const clock = LamportClock(5);
      expect(clock.observe(9).current, 9);
      expect(clock.observe(2).current, 5);
    });

    test('compares two clocks', () {
      expect(const LamportClock(3).isAfter(const LamportClock(2)), isTrue);
      expect(const LamportClock(2).isAfter(const LamportClock(3)), isFalse);
      expect(compareLamport(2, 3), isNegative);
      expect(compareLamport(3, 3), isZero);
      expect(compareLamport(4, 3), isPositive);
    });

    test('supports equality', () {
      expect(const LamportClock(3), const LamportClock(3));
      expect(const LamportClock(3).hashCode, const LamportClock(3).hashCode);
    });
  });

  group('Ulid', () {
    test('generates a 26 character identifier', () {
      final ulid = UlidGenerator().generate();
      expect(ulid.value, hasLength(26));
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(ulid.value), isTrue);
    });

    test('sorts by creation time', () {
      final generator = UlidGenerator();
      final first = generator.generate();
      final second = generator.generate();
      expect(second.compareTo(first), isPositive);
    });

    test(
      'keeps identifiers strictly increasing inside the same millisecond',
      () {
        var now = DateTime.utc(2026, 10, 25, 12);
        final generator = UlidGenerator(clock: () => now);
        final first = generator.generate();
        now = now.add(const Duration(milliseconds: 1));
        final second = generator.generate();
        expect(second.compareTo(first), isPositive);
      },
    );

    test('never goes backwards when the clock does', () {
      var now = DateTime.utc(2026, 10, 25, 12);
      final generator = UlidGenerator(clock: () => now);
      final first = generator.generate();
      now = now.subtract(const Duration(seconds: 5));
      final second = generator.generate();
      expect(second.compareTo(first), isPositive);
    });

    test('parses back the timestamp and the random part', () {
      final timestamp = DateTime.utc(2026, 10, 25, 12, 30);
      final ulid = Ulid.fromParts(
        timestamp: timestamp,
        randomPart: BigInt.from(123456789),
      );
      final parsed = Ulid.parse(ulid.value);
      expect(parsed.value, ulid.value);
      expect(parsed.timestamp, timestamp);
      expect(parsed.randomPart, BigInt.from(123456789));
    });

    test('rejects a malformed identifier', () {
      expect(
        () => Ulid.parse('too-short'),
        throwsA(isA<LimpidCoreException>()),
      );
      expect(
        () => Ulid.parse('0123456789012345678901234U'),
        throwsA(isA<LimpidCoreException>()),
      );
    });

    test('is deterministic with a seeded random source', () {
      final first = UlidGenerator(random: math.Random(42)).generate();
      final second = UlidGenerator(random: math.Random(42)).generate();
      expect(first.randomPart, second.randomPart);
    });
  });
}
