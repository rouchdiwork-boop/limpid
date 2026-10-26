import 'dart:async';

import 'package:limpid_app/src/data/relay_channel.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// A channel of the relay driven by the tests.
///
/// The fake publishes the events the test wants and records the cursors the
/// application announces. Closing it ends the stream: the transport opens
/// another channel, exactly as it does when the network cuts.
final class FakeRelayChannel implements RelayChannel {
  /// Creates a channel.
  FakeRelayChannel(this.documentId);

  /// The document the channel follows.
  final String documentId;

  final StreamController<TransportEvent> _controller =
      StreamController<TransportEvent>.broadcast();

  /// The cursors the application announced.
  final List<PresenceCursor> cursors = <PresenceCursor>[];

  /// Whether the channel was closed.
  bool isClosed = false;

  @override
  Stream<TransportEvent> events(String docId) => _controller.stream;

  @override
  Future<void> publishCursor(String docId, PresenceCursor cursor) async {
    cursors.add(cursor);
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    await _controller.close();
  }

  /// Publishes [event] towards the application.
  void emit(TransportEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// Publishes the operations [operations] towards the application.
  void emitOperations(List<SyncOp> operations) {
    emit(TransportOperationsReceived(documentId, operations));
  }

  /// Publishes the presence of [peer] towards the application.
  void emitPresence(PresencePeer peer) {
    emit(TransportPresenceReceived(documentId, peer));
  }

  /// Publishes the opening of the channel.
  void emitConnected() {
    emit(TransportConnected(documentId));
  }
}
