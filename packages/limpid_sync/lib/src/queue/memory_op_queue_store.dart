import 'dart:async';

import 'package:limpid_sync/src/queue/op_queue_store.dart';
import 'package:limpid_sync/src/queue/queued_op.dart';

/// An [OpQueueStore] keeping the entries in memory.
///
/// It is the implementation used by the tests and by the applications that
/// do not need to survive a restart.
final class InMemoryOpQueueStore implements OpQueueStore {
  /// Creates an empty store.
  InMemoryOpQueueStore();

  final Map<String, QueuedOp> _entries = <String, QueuedOp>{};
  final StreamController<List<QueuedOp>> _controller =
      StreamController<List<QueuedOp>>.broadcast();

  @override
  Future<void> put(QueuedOp op) async {
    _entries[op.operationKey] = op;
    _publish();
  }

  @override
  Future<void> putAll(Iterable<QueuedOp> ops) async {
    for (final op in ops) {
      _entries[op.operationKey] = op;
    }
    _publish();
  }

  @override
  Future<QueuedOp?> find(String operationKey) async => _entries[operationKey];

  @override
  Future<List<QueuedOp>> all() async =>
      List<QueuedOp>.unmodifiable(_entries.values.toList(growable: false));

  @override
  Future<void> remove(String operationKey) async {
    _entries.remove(operationKey);
    _publish();
  }

  @override
  Future<void> removeAll(Iterable<String> operationKeys) async {
    for (final key in operationKeys) {
      _entries.remove(key);
    }
    _publish();
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    _publish();
  }

  @override
  Stream<List<QueuedOp>> watch() => _controller.stream;

  /// Releases the resources held by the store.
  Future<void> dispose() => _controller.close();

  void _publish() {
    if (_controller.isClosed) return;
    _controller.add(
      List<QueuedOp>.unmodifiable(_entries.values.toList(growable: false)),
    );
  }
}
