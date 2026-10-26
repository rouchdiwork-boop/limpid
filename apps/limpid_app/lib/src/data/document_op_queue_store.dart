import 'package:limpid_sync/limpid_sync.dart';

/// The queue of the operations of a **single** document.
///
/// The durable queue of `limpid_sync` holds the operations of every document
/// of the library, in one table. The synchronisation client, on the other
/// hand, works on one document at a time: it applies the operations it
/// acknowledges to its own CRDT document, and an operation of another
/// document would be refused by the engine.
///
/// This store is the view that reconciles the two: it delegates every write
/// to the shared store of `limpid_sync` and hides the operations of the
/// other documents. The durability, the retries and the state machine stay
/// in `limpid_sync`; only the scope changes.
final class DocumentOpQueueStore implements OpQueueStore {
  /// Creates a view of [delegate] restricted to [documentId].
  DocumentOpQueueStore({required this.delegate, required this.documentId});

  /// The shared queue of the library.
  final OpQueueStore delegate;

  /// The document the view is restricted to.
  final String documentId;

  @override
  Future<void> put(QueuedOp op) async {
    if (op.documentId != documentId) return;
    await delegate.put(op);
  }

  @override
  Future<void> putAll(Iterable<QueuedOp> ops) async {
    await delegate.putAll(
      ops.where((QueuedOp op) => op.documentId == documentId),
    );
  }

  @override
  Future<QueuedOp?> find(String operationKey) async {
    final QueuedOp? entry = await delegate.find(operationKey);
    if (entry == null) return null;
    if (entry.documentId != documentId) return null;
    return entry;
  }

  @override
  Future<List<QueuedOp>> all() async {
    final List<QueuedOp> entries = await delegate.all();
    return List<QueuedOp>.unmodifiable(
      entries.where((QueuedOp entry) => entry.documentId == documentId),
    );
  }

  @override
  Future<void> remove(String operationKey) => delegate.remove(operationKey);

  @override
  Future<void> removeAll(Iterable<String> operationKeys) =>
      delegate.removeAll(operationKeys);

  @override
  Future<void> clear() async {
    final List<String> keys = (await all())
        .map((QueuedOp entry) => entry.operationKey)
        .toList(growable: false);
    if (keys.isEmpty) return;
    await delegate.removeAll(keys);
  }

  @override
  Stream<List<QueuedOp>> watch() => delegate.watch().map(
    (List<QueuedOp> entries) => List<QueuedOp>.unmodifiable(
      entries.where((QueuedOp entry) => entry.documentId == documentId),
    ),
  );
}
