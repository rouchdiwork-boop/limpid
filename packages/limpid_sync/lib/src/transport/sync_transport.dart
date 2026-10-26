import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/errors.dart';

/// The default number of operations requested by a single pull.
///
/// The value matches the batch limit of the API (`docs/ARCHITECTURE.md`
/// §6.1).
const int defaultPullLimit = 200;

/// The default timeout of a request sent to the API.
const Duration defaultRequestTimeout = Duration(seconds: 20);

/// The transport exchanging the CRDT operations with the API.
///
/// A transport is a thin, stateless-with-respect-to-the-document seam: the
/// orchestrator ([SyncClient]) owns the document, the queue and the cursor,
/// the transport only moves bytes.
///
/// ## Cursor contract
///
/// [pull] receives an opaque integer cursor and **must** return a contiguous
/// range of the operation log of the document, starting right after the
/// cursor. The orchestrator advances the cursor by the number of operations
/// it received, so a server that paginates must keep the log dense and
/// stable.
abstract interface class SyncTransport {
  /// Pushes [ops] to the API and returns what the server accepted.
  ///
  /// The call must be idempotent: replaying the same operations never
  /// duplicates them on the server.
  Future<PushResult> push(List<SyncOp> ops);

  /// Pulls the operations of [docId] that follow the cursor [since].
  ///
  /// At most [limit] operations are returned.
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit,
  });

  /// Opens the real-time channel of [docId].
  ///
  /// The returned stream is closed when the channel is closed.
  Stream<TransportEvent> connect(String docId);

  /// Releases the resources held by the transport.
  Future<void> dispose();
}

/// The result of a push round trip.
final class PushResult {
  /// Creates a push result.
  const PushResult({
    required this.accepted,
    required this.duplicated,
    required this.rejected,
    required this.lamportAck,
  });

  /// An empty result, used when there is nothing to push.
  static const PushResult empty = PushResult(
    accepted: <SyncOp>[],
    duplicated: <SyncOp>[],
    rejected: <RejectedOperation>[],
    lamportAck: 0,
  );

  /// The operations the server stored for the first time.
  final List<SyncOp> accepted;

  /// The operations the server already knew about.
  final List<SyncOp> duplicated;

  /// The operations the server refused, with the reason of the refusal.
  final List<RejectedOperation> rejected;

  /// The highest Lamport timestamp the server has seen for the document.
  final int lamportAck;

  /// The operations the server acknowledged, whether they were accepted or
  /// already known.
  List<SyncOp> get acknowledged => <SyncOp>[...accepted, ...duplicated];

  @override
  String toString() =>
      'PushResult(accepted: ${accepted.length}, '
      'duplicated: ${duplicated.length}, rejected: ${rejected.length})';
}

/// An operation the server refused to store.
final class RejectedOperation {
  /// Creates a rejected operation.
  const RejectedOperation({
    required this.operationKey,
    required this.code,
    required this.message,
  });

  /// The identity of the refused operation.
  final String operationKey;

  /// The stable, technical reason of the refusal.
  final String code;

  /// The human readable explanation of the refusal.
  final String message;

  @override
  String toString() => 'RejectedOperation($operationKey, $code)';
}

/// An event published by the real-time channel of a transport.
sealed class TransportEvent {
  /// Creates a transport event.
  const TransportEvent();

  /// The document the event belongs to.
  String get docId;

  /// The moment the event was produced, `null` when the transport does not
  /// timestamp its events.
  DateTime? get sentAt;
}

/// The real-time channel is open.
final class TransportConnected extends TransportEvent {
  /// Creates a connection event.
  const TransportConnected(this.docId, {this.sentAt});

  @override
  final String docId;

  @override
  final DateTime? sentAt;

  @override
  String toString() => 'TransportConnected($docId)';
}

/// The real-time channel is closed.
final class TransportDisconnected extends TransportEvent {
  /// Creates a disconnection event.
  const TransportDisconnected(this.docId, {this.reason, this.sentAt});

  @override
  final String docId;

  /// The reason of the disconnection, when the transport knows it.
  final Object? reason;

  @override
  final DateTime? sentAt;

  @override
  String toString() => 'TransportDisconnected($docId, $reason)';
}

/// Operations were received on the real-time channel.
final class TransportOperationsReceived extends TransportEvent {
  /// Creates an operations event.
  const TransportOperationsReceived(this.docId, this.operations, {this.sentAt});

  @override
  final String docId;

  /// The operations carried by the frame.
  final List<SyncOp> operations;

  @override
  final DateTime? sentAt;

  @override
  String toString() =>
      'TransportOperationsReceived($docId, ${operations.length} ops)';
}

/// The real-time channel reported an error.
final class TransportFailure extends TransportEvent {
  /// Creates a failure event.
  const TransportFailure(this.docId, this.error, {this.sentAt});

  @override
  final String docId;

  /// The error reported by the server.
  final SyncException error;

  @override
  final DateTime? sentAt;

  @override
  String toString() => 'TransportFailure($docId, $error)';
}

/// A peer was seen on the real-time channel.
///
/// The presence is the state of the **others**: a peer enters the document,
/// moves its cursor, and leaves it. The relay owns the states — a client
/// never announces that it left, it simply stops beating.
final class TransportPresenceReceived extends TransportEvent {
  /// Creates a presence event.
  const TransportPresenceReceived(this.docId, this.peer, {this.sentAt});

  @override
  final String docId;

  /// The peer the relay announced.
  final PresencePeer peer;

  @override
  final DateTime? sentAt;

  @override
  String toString() => 'TransportPresenceReceived($docId, $peer)';
}
