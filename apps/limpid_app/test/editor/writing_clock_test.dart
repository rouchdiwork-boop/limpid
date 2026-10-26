import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/editor/writing_clock.dart';

void main() {
  /// The moment the author sat down to write.
  final DateTime start = DateTime(2026, 10, 25, 9);

  test('la première frappe ne compte aucune minute', () {
    final ({WritingClock clock, int minutes}) counted = WritingClock.empty
        .advance(start);

    expect(counted.minutes, 0);
    expect(counted.clock.lastStrokeAt, start);
  });

  test('compte les minutes entre deux frappes', () {
    final WritingClock first = WritingClock.empty.advance(start).clock;

    final ({WritingClock clock, int minutes}) counted = first.advance(
      start.add(const Duration(seconds: 90)),
    );

    expect(counted.minutes, 1);
    expect(counted.clock.pendingSeconds, 30);
  });

  test('garde les secondes qui n’ont pas encore fait une minute', () {
    final WritingClock first = WritingClock.empty.advance(start).clock;
    final WritingClock second = first
        .advance(start.add(const Duration(seconds: 30)))
        .clock;

    final ({WritingClock clock, int minutes}) counted = second.advance(
      start.add(const Duration(seconds: 70)),
    );

    expect(counted.minutes, 1);
    expect(counted.clock.pendingSeconds, 10);
  });

  test('ne compte pas une longue absence', () {
    final WritingClock first = WritingClock.empty.advance(start).clock;

    final ({WritingClock clock, int minutes}) counted = first.advance(
      start.add(const Duration(hours: 2)),
    );

    expect(counted.minutes, 0);
  });

  test('reprend après une longue absence', () {
    final WritingClock first = WritingClock.empty.advance(start).clock;
    final WritingClock second = first
        .advance(start.add(const Duration(hours: 2)))
        .clock;

    final ({WritingClock clock, int minutes}) counted = second.advance(
      start.add(const Duration(hours: 2, seconds: 120)),
    );

    expect(counted.minutes, 2);
  });

  test('l’horloge est immuable', () {
    final WritingClock clock = WritingClock.empty;
    clock.advance(start.add(const Duration(minutes: 5)));

    expect(clock.lastStrokeAt, isNull);
    expect(clock.pendingSeconds, 0);
  });
}
