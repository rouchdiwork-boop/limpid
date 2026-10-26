import 'dart:io';

import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';

/// The context key holding the connection information of the caller.
const String connectionInfoKey = 'shelf.io.connection_info';

/// Returns the IP address of the caller.
String clientIpOf(Request request) {
  final Object? info = request.context[connectionInfoKey];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  final String? forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  return 'unknown';
}

/// A token bucket limiting the number of calls of a key.
///
/// The bucket holds [capacity] tokens and regains [refillPerSecond] tokens
/// per second. The state lives in memory: the limiter protects a single
/// instance of the API, which is the granularity the brief asks for.
final class TokenBucketRateLimiter {
  /// Creates a limiter.
  TokenBucketRateLimiter({
    required this.capacity,
    required this.refillPerSecond,
    this.keyCapacity = 10000,
  });

  /// The number of calls a key may burst.
  final int capacity;

  /// How many calls a key regains per second.
  final double refillPerSecond;

  /// The maximum number of tracked keys before the oldest ones are dropped.
  final int keyCapacity;

  final Map<String, _Bucket> _buckets = <String, _Bucket>{};

  /// Whether [key] may perform one more call.
  bool allow(String key) {
    final DateTime now = DateTime.now().toUtc();
    final _Bucket bucket = _buckets.putIfAbsent(
      key,
      () => _Bucket(now, capacity.toDouble()),
    );
    bucket.refill(now, refillPerSecond, capacity);
    if (bucket.tokens < 1) return false;
    bucket.tokens -= 1;
    return true;
  }

  /// The number of calls [key] may still perform.
  double remaining(String key) {
    final _Bucket? bucket = _buckets[key];
    if (bucket == null) return capacity.toDouble();
    return bucket.tokens;
  }

  /// Forgets the tracked keys, oldest first.
  void prune() {
    if (_buckets.length <= keyCapacity) return;
    final List<String> keys = _buckets.keys.toList(growable: false);
    for (var i = 0; i < keys.length - keyCapacity; i++) {
      _buckets.remove(keys[i]);
    }
  }
}

/// The mutable state of one token bucket.
final class _Bucket {
  _Bucket(this.updatedAt, this.tokens);

  DateTime updatedAt;
  double tokens;

  void refill(DateTime now, double refillPerSecond, int capacity) {
    final double elapsed = now.difference(updatedAt).inMicroseconds / 1000000;
    if (elapsed <= 0) return;
    tokens = (tokens + elapsed * refillPerSecond).clamp(0, capacity.toDouble());
    updatedAt = now;
  }
}

/// Builds the middleware limiting the rate of the selected routes.
///
/// [scope] names the bucket in the details of the answer, so a client knows
/// which limit it reached. [keyOf] names the caller the bucket belongs to:
/// by default the address of the caller, but an authenticated route is
/// better keyed by the account — a shared address must not exhaust the
/// quota of a single author.
Middleware rateLimitMiddleware({
  required TokenBucketRateLimiter limiter,
  required bool Function(Request request) applies,
  String scope = 'ai',
  String Function(Request request)? keyOf,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (applies(request)) {
        final String key = keyOf?.call(request) ?? clientIpOf(request);
        if (!limiter.allow(key)) {
          throw RateLimitedException(
            message:
                'Trop de requêtes envoyées en peu de temps. '
                'Patientez quelques instants avant de réessayer.',
            retryAfterSeconds: _retryAfter(limiter, key),
            details: <String, Object?>{'scope': scope},
          );
        }
        limiter.prune();
      }
      return innerHandler(request);
    };
  };
}

int _retryAfter(TokenBucketRateLimiter limiter, String key) {
  if (limiter.refillPerSecond <= 0) return 1;
  final double missing = 1 - limiter.remaining(key);
  final int seconds = (missing / limiter.refillPerSecond).ceil();
  return seconds < 1 ? 1 : seconds;
}
