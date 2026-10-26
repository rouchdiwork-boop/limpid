import 'package:limpid_core/limpid_core.dart' hide SyncTransport;

import 'repositories.dart';

/// An event of the real-time relay.
///
/// The relay is an **accelerator**: the queue of the synchronisation REST
/// remains the source of truth. The events tell the application what the
/// relay brought, and when the channel opened or closed.
sealed class RealTimeEvent {
  /// Creates an event.
  const RealTimeEvent(this.docId);

  /// The document the event belongs to.
  final String docId;
}

/// The relay delivered operations for the document.
///
/// The operations are CRDT operations like the others: the application
/// applies them to the document, exactly like the ones that come from the
/// synchronisation REST.
final class RealTimeOperations extends RealTimeEvent {
  /// Creates an event.
  const RealTimeOperations(super.docId, this.operations);

  /// The operations carried by the frame.
  final List<SyncOp> operations;

  @override
  String toString() => 'RealTimeOperations($docId, ${operations.length} ops)';
}

/// The relay announced a peer.
///
/// The peer is one of the **others**: the relay owns the presence, and the
/// application only displays it.
final class RealTimePresence extends RealTimeEvent {
  /// Creates an event.
  const RealTimePresence(super.docId, this.peer);

  /// The peer the relay announced.
  final PresencePeer peer;

  @override
  String toString() => 'RealTimePresence($docId, $peer)';
}

/// The channel of the document opened or closed.
///
/// The event is published when the channel opens — the first time and after
/// every reconnection — and when it closes. The application uses it to fall
/// back on the queue REST.
final class RealTimeConnection extends RealTimeEvent {
  /// Creates an event.
  const RealTimeConnection(super.docId, {required this.isConnected});

  /// Whether the channel is open.
  final bool isConnected;

  @override
  String toString() => 'RealTimeConnection($docId, $isConnected)';
}

/// A [SyncRepository] that follows the documents through the relay.
///
/// The contract of the synchronisation knows nothing of the relay: the
/// screens that want the presence check the capability, exactly as they
/// check the queue of the pending operations.
abstract interface class RealTimeSyncRepository implements SyncRepository {
  /// Follows the document [docId] and publishes the events of the relay.
  ///
  /// The operations the relay delivers are applied to the document before
  /// the event is published: the application reads the document and finds
  /// the text of the other author.
  Stream<RealTimeEvent> follow(String docId);

  /// Releases the document [docId].
  ///
  /// The call is a no-op when the document is not followed.
  Future<void> release(String docId);

  /// Announces the position of the caret of the author on [docId].
  Future<void> publishCursor(String docId, PresenceCursor cursor);
}
