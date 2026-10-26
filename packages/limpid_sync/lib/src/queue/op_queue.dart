import 'dart:math' as math;

import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/queue/op_queue_store.dart';
import 'package:limpid_sync/src/queue/queued_op.dart';
import 'package:limpid_sync/src/queue/retry_policy.dart';

/// The maximum number of operations sent in a single batch.
///
/// The value matches the batch limit of the API (`docs/ARCHITECTURE.md`
/// §6.1).
const int defaultPushBatchSize = 200;

/// The local, offline-first queue of the operations waiting to be sent.
///
/// The queue is the guarantee that nothing is lost while the application is
/// offline: an operation is persisted **before** the first attempt, and it
/// stays in the queue until the API acknowledges it.
///
/// The queue never mutates the entries it holds: every transition produces a
/// new [QueuedOp] that is written back to the [OpQueueStore].
final class OpQueue {
  /// Creates a queue on top of [store].
  OpQueue({
    required this.store,
    RetryPolicy retryPolicy = const RetryPolicy(),
    DateTime Function()? now,
    math.Random? random,
  }) : _policy = retryPolicy,
       _now = now ?? DateTime.now,
       _random = random ?? math.Random();

  /// The persistence of the queue.
  final OpQueueStore store;
  final RetryPolicy _policy;
  final DateTime Function() _now;
  final math.Random _random;

  /// The policy applied to the failed operations.
  RetryPolicy get retryPolicy => _policy;

  /// Adds [op] to the queue.
  ///
  /// The call is idempotent: an operation already present in the queue is
  /// not added twice, so a replayed local edit never produces two pushes.
  Future<void> enqueue(SyncOp op) async {
    final existing = await store.find(op.operationKey);
    if (existing != null) return;
    await store.put(QueuedOp.pending(op, createdAt: _now()));
  }

  /// Returns the operations that can be sent right now.
  ///
  /// The operations are sorted by increasing Lamport timestamp, as required
  /// by `docs/ARCHITECTURE.md` §5.6, and the failed ones are only returned
  /// once their backoff elapsed.
  Future<List<QueuedOp>> ready({int limit = defaultPushBatchSize}) async {
    final now = _now();
    final entries = await store.all();
    final candidates =
        entries
            .where(
              (entry) =>
                  entry.status != OpQueueStatus.sent &&
                  entry.attempts < _policy.maxAttempts &&
                  entry.isReadyAt(now),
            )
            .toList(growable: false)
          ..sort(_bySendOrder);
    if (candidates.length <= limit) {
      return List<QueuedOp>.unmodifiable(candidates);
    }
    return List<QueuedOp>.unmodifiable(candidates.take(limit));
  }

  /// Marks [ops] as acknowledged by the API.
  Future<void> markSent(Iterable<QueuedOp> ops) async {
    final now = _now();
    final updated = ops
        .map(
          (entry) => entry.copyWith(
            status: OpQueueStatus.sent,
            lastAttemptAt: now,
            clearNextAttemptAt: true,
          ),
        )
        .toList(growable: false);
    await store.putAll(updated);
  }

  /// Marks [op] as failed and schedules its next attempt.
  ///
  /// The delay grows exponentially with the number of attempts and is
  /// jittered, so a fleet of clients returning online at the same time does
  /// not hammer the API.
  Future<void> markFailed(QueuedOp op, {required String reason}) async {
    final now = _now();
    final attempts = op.attempts + 1;
    await store.put(
      op.copyWith(
        status: OpQueueStatus.failed,
        attempts: attempts,
        lastAttemptAt: now,
        nextAttemptAt: now.add(_policy.delayFor(attempts, random: _random)),
        lastError: reason,
      ),
    );
  }

  /// Removes the entries the API acknowledged.
  Future<void> purgeSent() async {
    final entries = await store.all();
    final sent = entries
        .where((entry) => entry.status == OpQueueStatus.sent)
        .map((entry) => entry.operationKey)
        .toList(growable: false);
    if (sent.isEmpty) return;
    await store.removeAll(sent);
  }

  /// The operations that still have to reach the API.
  Future<List<QueuedOp>> pending() async {
    final entries = await store.all();
    return List<QueuedOp>.unmodifiable(
      entries
          .where((entry) => entry.status != OpQueueStatus.sent)
          .toList(growable: false),
    );
  }

  /// The number of operations waiting to be sent.
  Future<int> pendingCount() async {
    final entries = await store.all();
    return entries.where((entry) => entry.status != OpQueueStatus.sent).length;
  }

  /// Removes the entry with [operationKey].
  Future<void> remove(String operationKey) => store.remove(operationKey);

  /// Publishes the content of the queue every time it changes.
  Stream<List<QueuedOp>> watch() => store.watch();

  /// Orders the entries by increasing Lamport timestamp, then by identity.
  static int _bySendOrder(QueuedOp a, QueuedOp b) {
    final byLamport = a.lamport.compareTo(b.lamport);
    if (byLamport != 0) return byLamport;
    return a.operationKey.compareTo(b.operationKey);
  }
}
