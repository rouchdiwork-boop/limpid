import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// The channel of the real-time relay for one document.
///
/// The port hides the WebSocket from the application: the transport drives
/// the channel, and the tests replace the network with a fake.
abstract interface class RelayChannel {
  /// The events the relay publishes for the document [docId].
  ///
  /// The stream ends when the channel closes.
  Stream<TransportEvent> events(String docId);

  /// Announces the position of the caret of the author on [docId].
  Future<void> publishCursor(String docId, PresenceCursor cursor);

  /// Closes the channel and releases its resources.
  Future<void> close();
}

/// The channel of the relay, based on the WebSocket transport of
/// `limpid_sync`.
///
/// The transport of the package speaks the protocol of the relay: it opens
/// the channel, joins the room of the document and publishes what it
/// receives.
final class WebSocketRelayChannel implements RelayChannel {
  /// Creates a channel.
  WebSocketRelayChannel({
    required this.rest,
    required this.baseUrl,
    required this.connector,
    required this.projectIdResolver,
    this.tokenProvider,
  }) : _transport = WebSocketSyncTransport(
         rest: rest,
         connector: connector,
         baseUrl: baseUrl,
         tokenProvider: tokenProvider,
         projectIdResolver: projectIdResolver,
       );

  /// The transport used for the push and the pull.
  final SyncTransport rest;

  /// The root of the API.
  final Uri baseUrl;

  /// Opens the channel of the relay.
  final WebSocketConnector connector;

  /// The project owning the document the client follows.
  final Future<String?> Function(String docId) projectIdResolver;

  /// The bearer token of the handshake.
  final AuthTokenProvider? tokenProvider;

  final WebSocketSyncTransport _transport;

  @override
  Stream<TransportEvent> events(String docId) => _transport.connect(docId);

  @override
  Future<void> publishCursor(String docId, PresenceCursor cursor) =>
      _transport.publishCursor(docId, cursor);

  @override
  Future<void> close() => _transport.dispose();
}
