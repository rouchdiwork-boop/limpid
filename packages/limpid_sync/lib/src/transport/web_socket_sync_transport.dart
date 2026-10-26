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

/// A [SyncTransport] that receives the operations in real time over a
/// WebSocket, and delegates the push and the pull to a REST transport.
///
/// The frames follow the contract of `docs/ARCHITECTURE.md` §6.6:
/// `{"type", "seq", "sent_at", "payload"}`.
final class WebSocketSyncTransport implements SyncTransport {
  /// Creates a real-time transport.
  WebSocketSyncTransport({
    required this.rest,
    required this.connector,
    required this.baseUrl,
    this.subprotocol = 'limpid.v1',
  });

  /// The transport used for the push and the pull.
  final SyncTransport rest;

  /// Opens the real-time channel.
  final WebSocketConnector connector;

  /// The root of the API, used to build the WebSocket URI.
  final Uri baseUrl;

  /// The sub-protocol announced during the handshake.
  final String subprotocol;

  WebSocketChannel? _channel;

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
    final WebSocketChannel channel;
    try {
      channel = await connector(
        _webSocketUri(),
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
    _channel = channel;
    yield TransportConnected(docId, sentAt: DateTime.now());
    channel.sink.add(
      jsonEncode(
        _frame('hello', <String, Object?>{
          'docs': <String>[docId],
        }),
      ),
    );
    Object? failure;
    try {
      await for (final message in channel.stream) {
        final event = _decodeFrame(message, docId);
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
    }
    _channel = null;
    yield TransportDisconnected(docId, reason: failure, sentAt: DateTime.now());
  }

  @override
  Future<void> dispose() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
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

  DateTime? _decodeSentAt(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  /// The WebSocket URI of the real-time endpoint.
  Uri _webSocketUri() {
    final path = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(
      scheme: baseUrl.scheme == 'http' ? 'ws' : 'wss',
      path: '$path/v1/sync',
      query: null,
    );
  }
}
