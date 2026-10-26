import 'package:limpid_sync/src/queue/queued_op.dart';

/// The persistence seam of the local operation queue.
///
/// The interface is deliberately small: the queue owns the retry policy and
/// the state machine, the store only persists the entries. It makes the
/// queue testable without a database and lets the application swap the
/// storage (SQLite in production, memory in the tests).
abstract interface class OpQueueStore {
  /// Inserts or replaces [op].
  Future<void> put(QueuedOp op);

  /// Inserts or replaces every entry of [ops].
  Future<void> putAll(Iterable<QueuedOp> ops);

  /// Returns the entry with [operationKey], `null` when it is unknown.
  Future<QueuedOp?> find(String operationKey);

  /// Returns every entry of the queue.
  Future<List<QueuedOp>> all();

  /// Removes the entry with [operationKey].
  Future<void> remove(String operationKey);

  /// Removes every entry of [operationKeys].
  Future<void> removeAll(Iterable<String> operationKeys);

  /// Removes every entry of the queue.
  Future<void> clear();

  /// Publishes the content of the queue every time it changes.
  Stream<List<QueuedOp>> watch();
}
