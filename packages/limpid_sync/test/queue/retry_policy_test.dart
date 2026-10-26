import 'dart:math';

import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('the delay grows exponentially and is capped', () {
      const policy = RetryPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 30),
        multiplier: 2,
        jitterRatio: 0,
      );

      expect(policy.delayFor(0), Duration.zero);
      expect(policy.delayFor(1), const Duration(seconds: 2));
      expect(policy.delayFor(2), const Duration(seconds: 4));
      expect(policy.delayFor(3), const Duration(seconds: 8));
      expect(policy.delayFor(4), const Duration(seconds: 16));
      expect(policy.delayFor(5), const Duration(seconds: 30));
      expect(policy.delayFor(20), const Duration(seconds: 30));
    });

    test('the jitter stays inside the bounds of the delay', () {
      const policy = RetryPolicy(
        baseDelay: Duration(seconds: 10),
        maxDelay: Duration(minutes: 5),
        jitterRatio: 0.25,
      );
      final random = Random(7);

      for (var attempt = 0; attempt < 50; attempt++) {
        final delay = policy.delayFor(1, random: random);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(7500));
        expect(delay.inMilliseconds, lessThanOrEqualTo(12500));
      }
    });

    test('the immediate policy retries without waiting', () {
      expect(RetryPolicy.immediate.delayFor(1), Duration.zero);
      expect(RetryPolicy.immediate.delayFor(5), Duration.zero);
    });
  });
}
