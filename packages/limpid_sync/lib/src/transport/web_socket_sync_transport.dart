import 'dart:async';
import 'dart:convert';

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/src/errors.dart';
import 'package:limpid_sync/src/transport/op_codec.dart';
import 'package:limpid_sync/src/transport/sync_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket channel towards [uri].
///
/// The connector is injected so the tests can replace the network with a
/// fake channel, and so the application can plug its own reconnection
/// policy.
typedef WebSocketConnector =
    Future<WebSocketChannel> Function(Uri uri, {Iterable<String>? protocols});

/// The default connector, based on `package:web_socket_channel`.
Future<WebSocketChannel> defaultWebSocketConnector(
  Uri uri, {
  Iterable<String>? protocols,
}) async {
  return WebSocketChannel.connect(uri, protocols: protocols);
}

/// The delay between two heartbeats of the relay.
///
/// The relay sends a `ping` to the clients that stayed silent, and the
/// clients answer. A peer that stops beating is purged by the relay.
const Duration defaultRelayHeartbeat = Duration(seconds: 25);

/// A [SyncTransport] that receives the operations in real time over a
/// WebSocket, and delegates the push and the pull to a REST transport.
///
/// The frames follow the contract of `docs/ARCHITECTURE.md` §6.6:
/// `{"type", "seq", "sent_at", "payload"}`.
///
/// ## The protocol of the relay
///
/// The relay is the authority: the client opens the channel, **joins** the
/// document it follows, and announces the position of its caret. The server
/// answers with an `ack`, relays the operations of the other clients, and
/// announces the presence of the peers.
///
/// ## The document and the project
///
/// The relay addresses a **room**, and a room is the pair
/// `(project, document)`: the client therefore has to name the project the
/// document belongs to. [projectIdResolver] answers it; a document the
/// device does not know is never joined.
final class WebSocketSyncTransport implements SyncTransport {
  /// Creates a real-time transport.
  WebSocketSyncTransport({
    required this.rest,
    required this.connector,
    required this.baseUrl,
    this.subprotocol = 'limpid.v1',
    this.projectIdResolver,
    this.tokenProvider,
    this.heartbeatInterval = defaultRelayHeartbeat,
  });

  /// The transport used for the push and the pull.
  final SyncTransport rest;

  /// Opens the real-time channel.
  final WebSocketConnector connector;

  /// The root of the API, used to build the WebSocket URI.
  final Uri baseUrl;

  /// The sub-protocol announced during the handshake.
  final String subprotocol;

  /// The project owning the document the client follows.
  ///
  /// The resolver answers `null` when the device does not know the document:
  /// the client then never joins the room, and the relay never sees it. The
  /// resolution is asynchronous: the device reads its own database to answer.
  final Future<String?> Function(String docId)? projectIdResolver;

  /// The bearer token carried by the handshake.
  ///
  /// The relay authenticates the connection when it opens: a browser cannot
  /// pose a header on a handshake, so the token travels in the query string.
  final Future<String?> Function()? tokenProvider;

  /// The delay between two heartbeats.
  final Duration heartbeatInterval;

  final Map<String, WebSocketChannel> _channels = <String, WebSocketChannel>{};

  final Map<String, Timer> _heartbeats = <String, Timer>{};

  @override
  Future<PushResult> push(List<SyncOp> ops) => rest.push(ops);

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) {
    return rest.pull(docId: docId, since: since, limit: limit);
  }

  @override
  Stream<TransportEvent> connect(String docId) async* {
    final String? projectId = await projectIdResolver?.call(docId);
    if (projectId == null) {
      yield TransportFailure(
        docId,
        SyncTransportException(
          'The document belongs to no known project.',
          code: 'sync_unknown_project',
        ),
        sentAt: DateTime.now(),
      );
      return;
    }

    final WebSocketChannel channel;
    try {
      channel = await connector(
        await _webSocketUri(),
        protocols: <String>[subprotocol],
      );
    } on Object catch (error) {
      yield TransportFailure(
        docId,
        SyncTransportException(
          'The real-time channel could not be opened: $error',
          code: 'sync_unreachable',
          isNetworkFailure: true,
          cause: error,
        ),
        sentAt: DateTime.now(),
      );
      return;
    }
    _channels[docId] = channel;
    yield TransportConnected(docId, sentAt: DateTime.now());

    channel.sink.add(
      jsonEncode(
        _frame('join', <String, Object?>{
          'project_id': projectId,
          'doc_id': docId,
        }),
      ),
    );
    _startHeartbeat(docId, channel);

    Object? failure;
    try {
      await for (final message in channel.stream) {
        final TransportEvent? event = _decodeFrame(message, docId);
        if (event != null) yield event;
      }
    } on Object catch (error) {
      failure = error;
      yield TransportFailure(
        docId,
        SyncTransportException(
          'The real-time channel failed: $error',
          code: 'sync_channel_error',
          cause: error,
        ),
        sentAt: DateTime.now(),
      );
    } finally {
      // Le canal est fermé : le battement s'arrête, même quand le client
      // abandonne la lecture du flux.
      _stopHeartbeat(docId);
      _channels.remove(docId);
    }
    yield TransportDisconnected(docId, reason: failure, sentAt: DateTime.now());
  }

  @override
  Future<void> dispose() async {
    for (final String docId in _heartbeats.keys.toList(growable: false)) {
      _stopHeartbeat(docId);
    }
    final List<WebSocketChannel> channels = _channels.values.toList(
      growable: false,
    );
    _channels.clear();
    for (final WebSocketChannel channel in channels) {
      await channel.sink.close();
    }
  }

  /// Announces the position of the caret of the author on [docId].
  ///
  /// The call is a no-op when the document is not followed: the relay only
  /// knows the positions of the clients that joined the room.
  Future<void> publishCursor(String docId, PresenceCursor cursor) async {
    final WebSocketChannel? channel = _channels[docId];
    if (channel == null) return;
    final String? projectId = await projectIdResolver?.call(docId);
    if (projectId == null) return;
    channel.sink.add(
      jsonEncode(
        _frame('cursor', <String, Object?>{
          'project_id': projectId,
          'doc_id': docId,
          'cursor': <String, Object?>{
            'block_id': cursor.blockId,
            'offset': cursor.offset,
          },
        }),
      ),
    );
  }

  /// Starts the heartbeat of the document [docId].
  ///
  /// The client beats every [heartbeatInterval]: the relay purges the peers
  /// that stopped beating, and the client is one of them.
  void _startHeartbeat(String docId, WebSocketChannel channel) {
    _stopHeartbeat(docId);
    _heartbeats[docId] = Timer.periodic(heartbeatInterval, (Timer _) {
      channel.sink.add(jsonEncode(_frame('ping', <String, Object?>{})));
    });
  }

  /// Stops the heartbeat of the document [docId].
  void _stopHeartbeat(String docId) {
    _heartbeats.remove(docId)?.cancel();
  }

  /// Builds a protocol frame.
  Map<String, Object?> _frame(String type, Map<String, Object?> payload) {
    return <String, Object?>{
      'type': type,
      'seq': 0,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
  }

  /// Decodes a frame received on the channel.
  TransportEvent? _decodeFrame(Object? message, String docId) {
    if (message is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final sentAt = _decodeSentAt(decoded['sent_at']);
    final type = decoded['type'];
    final payload = decoded['payload'];
    switch (type) {
      case 'op':
        if (payload is! Map<String, Object?>) return null;
        return TransportOperationsReceived(docId, <SyncOp>[
          OpCodec.decode(payload),
        ], sentAt: sentAt);
      case 'presence':
        if (payload is! Map<String, Object?>) return null;
        final PresencePeer? peer = PresenceCodec.decode(payload);
        if (peer == null) return null;
        return TransportPresenceReceived(docId, peer, sentAt: sentAt);
      case 'ping':
        // Le relais garde-fou : le client répond et la trame est sans effet.
        _answerPong(docId);
        return null;
      case 'error':
        if (payload is! Map<String, Object?>) return null;
        final code = payload['code'];
        final message = payload['message'];
        return TransportFailure(
          docId,
          SyncTransportException(
            message is String ? message : 'The server reported an error.',
            code: code is String ? code : 'sync_channel_error',
          ),
          sentAt: sentAt,
        );
      default:
        return null;
    }
  }

  /// Answers the `ping` of the relay with a `pong`.
  void _answerPong(String docId) {
    final WebSocketChannel? channel = _channels[docId];
    if (channel == null) return;
    channel.sink.add(jsonEncode(_frame('pong', <String, Object?>{})));
  }

  DateTime? _decodeSentAt(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  /// The WebSocket URI of the real-time endpoint.
  ///
  /// The token travels in the query string: the relay authenticates the
  /// connection when it opens, and a browser cannot pose a header on a
  /// handshake.
  Future<Uri> _webSocketUri() async {
    final path = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    final String? token = await tokenProvider?.call();
    return baseUrl.replace(
      scheme: baseUrl.scheme == 'http' ? 'ws' : 'wss',
      path: '$path/v1/sync',
      queryParameters: (token == null || token.isEmpty)
          ? null
          : <String, String>{'token': token},
    );
  }
}
