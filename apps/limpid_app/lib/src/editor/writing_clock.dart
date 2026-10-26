import 'package:flutter/foundation.dart';

/// The time the author spent writing.
///
/// The clock counts the time **between two strokes**: the author is writing
/// while the strokes follow each other. A long pause ends the burst — past
/// [maxBurst], the author was away, not writing.
///
/// The clock is **immutable**: every stroke returns a new clock. The
/// controller keeps the clock of the session and replaces it.
///
/// ## The minutes of a day
///
/// The clock hands out whole minutes, and keeps the seconds that were not
/// counted yet: the writing of a morning is not lost because the author
/// paused for forty seconds between two paragraphs.
@immutable
final class WritingClock {
  /// Creates a clock.
  const WritingClock({this.lastStrokeAt, this.pendingSeconds = 0});

  /// The clock of a session that has not started.
  static const WritingClock empty = WritingClock();

  /// The longest pause that still counts as writing.
  static const Duration maxBurst = Duration(minutes: 15);

  /// The number of seconds in a minute.
  static const int secondsPerMinute = 60;

  /// The moment of the last stroke, `null` when nothing was written yet.
  final DateTime? lastStrokeAt;

  /// The seconds of writing that were not counted as a minute yet.
  final int pendingSeconds;

  /// Counts the writing that happened until [moment].
  ///
  /// The result holds the clock to keep and the minutes to write in the
  /// session of the day.
  ({WritingClock clock, int minutes}) advance(DateTime moment) {
    final DateTime? last = lastStrokeAt;
    if (last == null) {
      return (
        clock: WritingClock(
          lastStrokeAt: moment,
          pendingSeconds: pendingSeconds,
        ),
        minutes: 0,
      );
    }

    final int elapsed = moment.difference(last).inSeconds;
    if (elapsed > maxBurst.inSeconds) {
      // L'auteur s'est absenté : la salve est finie, et les secondes qui
      // attendaient une minute appartiennent à la salve précédente.
      return (clock: WritingClock(lastStrokeAt: moment), minutes: 0);
    }

    final int total = pendingSeconds + (elapsed > 0 ? elapsed : 0);
    final int minutes = total ~/ secondsPerMinute;
    return (
      clock: WritingClock(
        lastStrokeAt: moment,
        pendingSeconds: total - minutes * secondsPerMinute,
      ),
      minutes: minutes,
    );
  }
}
