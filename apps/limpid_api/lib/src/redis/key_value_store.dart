import 'redis_client.dart';

/// A short lived key/value store.
///
/// The API uses it for the idempotency keys (ARCHITECTURE.md §6.5) and for
/// the readiness probe.
abstract interface class KeyValueStore {
  /// Stores [value] under [key], optionally with a time to live.
  Future<void> set(String key, String value, {Duration? ttl});

  /// Reads the value of [key], `null` when the key is unknown or expired.
  Future<String?> get(String key);

  /// Removes [key].
  Future<void> delete(String key);

  /// Whether the store answers.
  Future<bool> ping();
}

/// A [KeyValueStore] backed by Redis.
final class RedisKeyValueStore implements KeyValueStore {
  /// Creates a store on top of [client].
  const RedisKeyValueStore(this.client);

  /// The Redis client.
  final RedisClient client;

  @override
  Future<void> set(String key, String value, {Duration? ttl}) async {
    if (ttl == null) {
      await client.command(<String>['SET', key, value]);
      return;
    }
    await client.command(<String>[
      'SET',
      key,
      value,
      'PX',
      '${ttl.inMilliseconds}',
    ]);
  }

  @override
  Future<String?> get(String key) async {
    final Object? reply = await client.command(<String>['GET', key]);
    return reply is String ? reply : null;
  }

  @override
  Future<void> delete(String key) async {
    await client.command(<String>['DEL', key]);
  }

  @override
  Future<bool> ping() async {
    final Object? reply = await client.command(<String>['PING']);
    return reply == 'PONG';
  }
}

/// An in-memory [KeyValueStore], used by the test suite.
final class InMemoryKeyValueStore implements KeyValueStore {
  /// Creates an empty store.
  InMemoryKeyValueStore({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final Map<String, String> _values = <String, String>{};
  final Map<String, DateTime> _expiries = <String, DateTime>{};

  @override
  Future<void> set(String key, String value, {Duration? ttl}) async {
    _values[key] = value;
    if (ttl == null) {
      _expiries.remove(key);
      return;
    }
    _expiries[key] = _clock().add(ttl);
  }

  @override
  Future<String?> get(String key) async {
    final DateTime? expiry = _expiries[key];
    if (expiry != null && !_clock().isBefore(expiry)) {
      _values.remove(key);
      _expiries.remove(key);
      return null;
    }
    return _values[key];
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    _expiries.remove(key);
  }

  @override
  Future<bool> ping() async => true;
}
