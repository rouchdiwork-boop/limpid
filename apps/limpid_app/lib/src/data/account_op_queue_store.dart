import 'package:limpid_sync/limpid_sync.dart';

/// The queue of the operations of one account.
///
/// ## The leak this view closes
///
/// The table of the queue is unique per device: it holds the modifications
/// that have not yet reached the server, whatever the account that produced
/// them. Read as it is, the queue of one account would be pushed under the
/// session of another — the manuscript of an author would leave the device
/// in the name of somebody else.
///
/// ## The author is the account
///
/// The rows of the queue carry the author of the operation, and the device
/// stamps the operations it produces with the author of the session — the
/// account that owns them. The view therefore keeps the rows of the current
/// account and hides the others. The operations of a collaborator are not
/// pushed back by the device either: the server already knows them.
///
/// The account is resolved on every call: a change of account takes effect
/// at once, without reopening the database.
final class AccountOpQueueStore implements OpQueueStore {
  /// Creates a view of [delegate] restricted to the account of [accountId].
  AccountOpQueueStore({required this.delegate, required this.accountId});

  /// The shared queue of the device.
  final OpQueueStore delegate;

  /// The identifier of the account whose operations the view exposes.
  final String Function() accountId;

  @override
  Future<void> put(QueuedOp op) async {
    if (!_belongsToTheAccount(op)) return;
    await delegate.put(op);
  }

  @override
  Future<void> putAll(Iterable<QueuedOp> ops) async {
    final List<QueuedOp> mine = ops
        .where(_belongsToTheAccount)
        .toList(growable: false);
    if (mine.isEmpty) return;
    await delegate.putAll(mine);
  }

  @override
  Future<QueuedOp?> find(String operationKey) async {
    final QueuedOp? entry = await delegate.find(operationKey);
    if (entry == null) return null;
    return _belongsToTheAccount(entry) ? entry : null;
  }

  @override
  Future<List<QueuedOp>> all() async {
    final List<QueuedOp> entries = await delegate.all();
    return List<QueuedOp>.unmodifiable(entries.where(_belongsToTheAccount));
  }

  @override
  Future<void> remove(String operationKey) async {
    final QueuedOp? entry = await delegate.find(operationKey);
    if (entry == null) return;
    if (!_belongsToTheAccount(entry)) return;
    await delegate.remove(operationKey);
  }

  @override
  Future<void> removeAll(Iterable<String> operationKeys) async {
    final List<QueuedOp> entries = await delegate.all();
    final List<String> mine = entries
        .where(_belongsToTheAccount)
        .map((QueuedOp entry) => entry.operationKey)
        .where(operationKeys.contains)
        .toList(growable: false);
    if (mine.isEmpty) return;
    await delegate.removeAll(mine);
  }

  @override
  Future<void> clear() async {
    final List<QueuedOp> entries = await delegate.all();
    final List<String> mine = entries
        .where(_belongsToTheAccount)
        .map((QueuedOp entry) => entry.operationKey)
        .toList(growable: false);
    if (mine.isEmpty) return;
    await delegate.removeAll(mine);
  }

  @override
  Stream<List<QueuedOp>> watch() => delegate.watch().map(
    (List<QueuedOp> entries) =>
        List<QueuedOp>.unmodifiable(entries.where(_belongsToTheAccount)),
  );

  /// Whether [entry] belongs to the account of the session.
  bool _belongsToTheAccount(QueuedOp entry) => entry.authorId == accountId();
}
