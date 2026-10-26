import 'dart:async';

/// The key of a room of the relay.
///
/// A room is a **pair**: a document is only reachable through the project
/// that owns it, so the same `doc_id` in two projects gives two rooms that
/// never meet.
typedef SyncRoomKey = (String projectId, String docId);

/// A subscriber of a synchronised document.
final class SyncSubscription {
  SyncSubscription._(this.projectId, this.docId, this.userId, this._controller);

  /// The project the subscription follows.
  final String projectId;

  /// The document the subscription follows.
  final String docId;

  /// The author of the subscription.
  final String userId;

  final StreamController<Map<String, Object?>> _controller;

  /// The room the subscription belongs to.
  SyncRoomKey get room => (projectId, docId);

  /// The frames addressed to the subscriber.
  Stream<Map<String, Object?>> get frames => _controller.stream;

  /// Closes the subscription.
  void close() {
    if (!_controller.isClosed) _controller.close();
  }
}

/// The relay of the operations of the synchronised documents.
///
/// The hub never modifies the content of an operation: it only transmits it.
/// The convergence stays the property of the CRDT (ARCHITECTURE.md §6.6).
///
/// The rooms are keyed by the pair `(projectId, docId)`: a document id alone
/// would let a subscription of one project receive the operations of another
/// project, and would let an operation written in one project be broadcast
/// into the room of another.
final class SyncHub {
  /// Creates a hub.
  SyncHub();

  final Map<SyncRoomKey, Set<SyncSubscription>> _rooms =
      <SyncRoomKey, Set<SyncSubscription>>{};

  /// The number of subscribers of the room of [projectId] and [docId].
  int subscriberCount(String projectId, String docId) =>
      _rooms[(projectId, docId)]?.length ?? 0;

  /// Subscribes a client to the document [docId] of the project [projectId].
  SyncSubscription join({
    required String projectId,
    required String docId,
    required String userId,
  }) {
    final SyncSubscription subscription = SyncSubscription._(
      projectId,
      docId,
      userId,
      StreamController<Map<String, Object?>>.broadcast(),
    );
    _rooms
        .putIfAbsent(subscription.room, () => <SyncSubscription>{})
        .add(subscription);
    return subscription;
  }

  /// Removes [subscription] from its room.
  void leave(SyncSubscription subscription) {
    final Set<SyncSubscription>? room = _rooms[subscription.room];
    if (room == null) return;
    room.remove(subscription);
    if (room.isEmpty) _rooms.remove(subscription.room);
    subscription.close();
  }

  /// Transmits [frame] to every subscriber of the document [docId] of the
  /// project [projectId].
  ///
  /// [except] designates the subscriber that produced the frame: it does not
  /// receive its own message. The other devices of the same author do.
  void broadcast(
    String projectId,
    String docId,
    Map<String, Object?> frame, {
    SyncSubscription? except,
  }) {
    final Set<SyncSubscription>? room = _rooms[(projectId, docId)];
    if (room == null) return;
    for (final SyncSubscription subscription in room) {
      if (identical(subscription, except)) {
        continue;
      }
      subscription._controller.add(frame);
    }
  }

  /// Closes every subscription.
  void close() {
    for (final Set<SyncSubscription> room in _rooms.values) {
      for (final SyncSubscription subscription in room) {
        subscription.close();
      }
    }
    _rooms.clear();
  }
}
