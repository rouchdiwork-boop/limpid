import 'dart:math' as math;

/// A Lamport logical clock (D-04).
///
/// The clock is immutable: every operation returns a new clock instance, so
/// a clock can be shared or stored without any risk of aliasing.
final class LamportClock {
  /// Creates a clock positioned at [current].
  const LamportClock([this.current = 0]);

  /// The current logical time.
  final int current;

  /// Registers a local event and returns the clock advanced by one tick.
  LamportClock tick() => LamportClock(current + 1);

  /// Registers the reception of a remote event stamped [remoteValue].
  ///
  /// The new logical time is `max(current, remoteValue) + 1`, which guarantees
  /// that a received event is always strictly newer than the event that
  /// produced it.
  LamportClock receive(int remoteValue) =>
      LamportClock(math.max(current, remoteValue) + 1);

  /// Observes a remote event without generating a local one.
  LamportClock observe(int remoteValue) =>
      LamportClock(math.max(current, remoteValue));

  /// Whether [other] is strictly more recent than this clock.
  bool isAfter(LamportClock other) => current > other.current;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LamportClock && other.current == current);

  @override
  int get hashCode => current.hashCode;

  @override
  String toString() => 'LamportClock($current)';
}

/// Compares two Lamport timestamps.
///
/// Returns a negative number when [a] is older than [b], zero when they are
/// equal and a positive number when [a] is newer than [b].
int compareLamport(int a, int b) => a.compareTo(b);
