import 'dart:async';

import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/relay_channel.dart';
import 'package:limpid_app/src/domain/realtime.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// The real-time channel of the application.
///
/// The transport opens the WebSocket of the relay — `WS /v1/sync` — and
/// publishes what it receives. The push and the pull stay on the REST
/// transport: the relay is an accelerator, never the source of truth.
///
/// ## The reconnection
///
/// The network cuts, the machine sleeps, the relay restarts: the channel
/// closes and the transport opens it again, with a delay that grows up to
/// [maxReconnectDelay]. Every reconnection publishes a
/// [RealTimeConnection], and the application catches up with the queue REST.
final class RealTimeTransport {
  /// Creates a transport.
  RealTimeTransport({
    required this.baseUrl,
    required this.store,
    required this.rest,
    this.tokenProvider,
    this.accountId,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.channelFactory,
  });

  /// The root of the API.
  final Uri baseUrl;

  /// The local database, used to resolve the project of a document.
  final ManuscriptStore store;

  /// The transport used for the push and the pull.
  final SyncTransport rest;

  /// The bearer token of the handshake.
  final AuthTokenProvider? tokenProvider;

  /// The account that owns the local data of the device.
  final String Function()? accountId;

  /// The delay before the first reconnection.
  final Duration reconnectDelay;

  /// The longest delay between two reconnections.
  final Duration maxReconnectDelay;

  /// The factory of the channels of the relay.
  ///
  /// The tests replace the network with a fake; the application uses the
  /// WebSocket of `limpid_sync`.
  final RelayChannel Function(String docId)? channelFactory;

  final Map<String, _Relay> _relays = <String, _Relay>{};

  /// The events of the relay for the document [docId].
  ///
  /// The call opens the channel of the document when it is closed. The
  /// caller releases it with [release] when it stops following the document.
  Stream<RealTimeEvent> watch(String docId) {
    return _relayOf(docId).events.stream;
  }

  /// Releases the channel of the document [docId].
  ///
  /// The call is a no-op when the document is not followed: the channel
  /// stays open as long as somebody watches it.
  Future<void> release(String docId) async {
    final _Relay? relay = _relays[docId];
    if (relay == null) return;
    await relay.close();
    _relays.remove(docId);
  }

  /// Announces the position of the caret of the author on [docId].
  ///
  /// The call is a no-op when the document is not followed: the relay only
  /// knows the positions of the clients that joined the room.
  Future<void> publishCursor(String docId, PresenceCursor cursor) async {
    final _Relay? relay = _relays[docId];
    if (relay == null) return;
    await relay.publishCursor(cursor);
  }

  /// Whether the channel of the document [docId] is open.
  bool isConnected(String docId) => _relays[docId]?.isConnected ?? false;

  /// Closes every channel of the transport.
  Future<void> dispose() async {
    final List<_Relay> relays = _relays.values.toList(growable: false);
    _relays.clear();
    for (final _Relay relay in relays) {
      await relay.close();
    }
  }

  /// The relay of the document [docId], opened when it does not exist yet.
  _Relay _relayOf(String docId) {
    return _relays.putIfAbsent(docId, () {
      final _Relay relay = _Relay(docId: docId, owner: this);
      relay.open();
      return relay;
    });
  }

  /// The project owning the document [docId], `null` when the device does
  /// not know it.
  Future<String?> projectOf(String docId) {
    final String? account = accountId?.call();
    return store.findProjectOfDocument(docId, accountId: account);
  }

  /// The channel of the document [docId].
  RelayChannel _channelOf(String docId) {
    final RelayChannel Function(String docId)? factory = channelFactory;
    if (factory != null) return factory(docId);
    return WebSocketRelayChannel(
      rest: rest,
      baseUrl: baseUrl,
      connector: defaultWebSocketConnector,
      projectIdResolver: projectOf,
      tokenProvider: tokenProvider,
    );
  }
}

/// The channel of the relay for one document.
final class _Relay {
  _Relay({required this.docId, required this.owner});

  /// The document the channel follows.
  final String docId;

  /// The transport that owns the channel.
  final RealTimeTransport owner;

  /// The events published to the application.
  final StreamController<RealTimeEvent> events =
      StreamController<RealTimeEvent>.broadcast();

  RelayChannel? _channel;

  StreamSubscription<TransportEvent>? _subscription;

  Timer? _reconnection;

  int _attempt = 0;

  bool _isClosed = false;

  bool _isConnected = false;

  /// Whether the channel is open.
  bool get isConnected => _channel != null;

  /// Opens the channel, and opens it again after every closure.
  void open() {
    if (_isClosed) return;
    final RelayChannel channel = owner._channelOf(docId);
    _channel = channel;
    _subscription = channel
        .events(docId)
        .listen(
          _onEvent,
          onDone: _onClosed,
          onError: (Object _) => _onClosed(),
        );
  }

  /// Announces the position of the caret of the author.
  Future<void> publishCursor(PresenceCursor cursor) async {
    await _channel?.publishCursor(docId, cursor);
  }

  /// Closes the channel and releases the resources.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _reconnection?.cancel();
    _reconnection = null;
    await _subscription?.cancel();
    _subscription = null;
    final RelayChannel? channel = _channel;
    _channel = null;
    await channel?.close();
    await events.close();
  }

  /// Publishes what the relay brought.
  void _onEvent(TransportEvent event) {
    if (_isClosed) return;
    switch (event) {
      case TransportConnected():
        _attempt = 0;
        _isConnected = true;
        events.add(RealTimeConnection(docId, isConnected: true));
      case TransportOperationsReceived(:final List<SyncOp> operations):
        events.add(RealTimeOperations(docId, operations));
      case TransportPresenceReceived(:final PresencePeer peer):
        events.add(RealTimePresence(docId, peer));
      case TransportDisconnected():
        _publishDisconnected();
      case TransportFailure():
        break;
    }
  }

  /// Publishes the closure of the channel.
  ///
  /// The closure is published once: the transport may learn it from the
  /// event of the channel and from the end of its stream.
  void _publishDisconnected() {
    if (!_isConnected) return;
    _isConnected = false;
    events.add(RealTimeConnection(docId, isConnected: false));
  }

  /// Schedules the reconnection of the channel.
  void _onClosed() {
    if (_isClosed) return;
    _channel = null;
    _subscription = null;
    _publishDisconnected();
    _attempt++;
    final Duration delay = _delayOf(_attempt);
    _reconnection?.cancel();
    _reconnection = Timer(delay, open);
  }

  /// The delay before the reconnection number [attempt].
  Duration _delayOf(int attempt) {
    final int milliseconds =
        owner.reconnectDelay.inMilliseconds * (1 << (attempt - 1).clamp(0, 8));
    return Duration(
      milliseconds: milliseconds.clamp(
        owner.reconnectDelay.inMilliseconds,
        owner.maxReconnectDelay.inMilliseconds,
      ),
    );
  }
}
