import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../errors/app_exception.dart';
import '../redis/key_value_store.dart';

/// How long an idempotency key is remembered.
const Duration idempotencyTtl = Duration(hours: 24);

/// The outcome of the idempotency check of a call.
enum IdempotencyStatus {
  /// The call was never made with this key: it must be executed.
  fresh,

  /// The call was already made with this key and the same body: the stored
  /// answer must be replayed.
  replay,
}

/// The outcome of the idempotency check.
final class IdempotencyOutcome {
  /// Creates an outcome.
  const IdempotencyOutcome({required this.status, this.storedResponse});

  /// Whether the call must run or must be replayed.
  final IdempotencyStatus status;

  /// The answer of the first call, when the call must be replayed.
  final String? storedResponse;
}

/// Guards the calls with a side effect against their repetition.
///
/// The key and the fingerprint of the body are kept for twenty four hours
/// (ARCHITECTURE.md §6.5): the same key with the same body replays the first
/// answer, the same key with a different body is a conflict.
///
/// The keys are scoped to the caller: the owner comes from the authenticated
/// context of the route, never from the body of the request. Two accounts
/// using the same key never share an answer, and neither of them blocks the
/// other.
final class IdempotencyService {
  /// Creates a service.
  const IdempotencyService({required this.store, this.ttl = idempotencyTtl});

  /// The store holding the keys.
  final KeyValueStore store;

  /// How long a key is remembered.
  final Duration ttl;

  /// Checks whether [key] was already used by [ownerId].
  ///
  /// Throws an [IdempotencyKeyConflictException] when the key was used with
  /// another body.
  Future<IdempotencyOutcome> begin({
    required String ownerId,
    required String key,
    required String body,
  }) async {
    final String fingerprint = fingerprintOf(body);
    final String? stored = await store.get(_storageKey(ownerId, key));
    if (stored == null) {
      return const IdempotencyOutcome(status: IdempotencyStatus.fresh);
    }

    final Map<String, dynamic> record = _decode(stored);
    final Object? storedFingerprint = record['fingerprint'];
    if (storedFingerprint is! String || storedFingerprint != fingerprint) {
      throw const IdempotencyKeyConflictException();
    }
    final Object? response = record['response'];
    return IdempotencyOutcome(
      status: IdempotencyStatus.replay,
      storedResponse: response is String ? response : null,
    );
  }

  /// Stores the answer of the first call made with [key] by [ownerId].
  Future<void> complete({
    required String ownerId,
    required String key,
    required String body,
    required String response,
  }) async {
    final String payload = jsonEncode(<String, Object?>{
      'fingerprint': fingerprintOf(body),
      'response': response,
    });
    await store.set(_storageKey(ownerId, key), payload, ttl: ttl);
  }

  /// Computes the fingerprint of a request body.
  static String fingerprintOf(String body) {
    return sha256.convert(utf8.encode(body)).toString();
  }

  /// The key under which the answer of [ownerId] is stored.
  static String _storageKey(String ownerId, String key) =>
      'idempotency:$ownerId:$key';

  static Map<String, dynamic> _decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }
}
