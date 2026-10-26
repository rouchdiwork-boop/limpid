import 'dart:math' as math;

/// The exponential backoff applied to the failed operations of the queue.
///
/// The delay grows exponentially with the number of attempts, is capped by
/// [maxDelay] and is jittered so that the clients returning online at the
/// same time do not all retry at the same instant.
final class RetryPolicy {
  /// Creates a retry policy.
  const RetryPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2.0,
    this.jitterRatio = 0.25,
    this.maxAttempts = 12,
  });

  /// A policy that retries immediately, used by the tests.
  static const RetryPolicy immediate = RetryPolicy(
    baseDelay: Duration.zero,
    maxDelay: Duration.zero,
    jitterRatio: 0,
  );

  /// The delay before the first retry.
  final Duration baseDelay;

  /// The longest delay between two attempts.
  final Duration maxDelay;

  /// The factor applied to the delay after each attempt.
  final double multiplier;

  /// The relative amplitude of the jitter, `0` disables it.
  final double jitterRatio;

  /// The number of attempts after which an operation is left aside.
  final int maxAttempts;

  /// The delay to observe before the attempt number [attempts].
  ///
  /// [attempts] counts the failures already observed: `1` is the delay after
  /// the first failure.
  Duration delayFor(int attempts, {math.Random? random}) {
    if (attempts <= 0) return Duration.zero;
    var millis = baseDelay.inMilliseconds.toDouble();
    for (var index = 1; index < attempts; index++) {
      millis *= multiplier;
      if (millis >= maxDelay.inMilliseconds) break;
    }
    final ceiling = maxDelay.inMilliseconds.toDouble();
    millis = millis.clamp(0, ceiling);
    if (jitterRatio > 0 && random != null) {
      final spread = millis * jitterRatio;
      millis = millis - spread + (random.nextDouble() * spread * 2);
      millis = millis.clamp(0, ceiling);
    }
    return Duration(milliseconds: millis.round());
  }
}
