import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A fake [WebSocketChannel] driven by the tests.
///
/// The test pushes the frames it wants to send with [emit] and reads the
/// frames sent by the client with [sent].
final class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  /// Creates a channel.
  FakeWebSocketChannel();

  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();

  /// The frames sent by the client, in order.
  final List<Object?> _sent = <Object?>[];

  late final FakeWebSocketSink _sink = FakeWebSocketSink(_sent);

  /// The frames sent by the client, in order.
  List<Object?> get sent => List<Object?>.unmodifiable(_sent);

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => 'limpid.v1';

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  /// Emits [frame] towards the client.
  void emit(Object? frame) {
    if (_incoming.isClosed) return;
    _incoming.add(frame);
  }

  /// Emits a protocol frame of [type] carrying [payload].
  void emitFrame(String type, Map<String, Object?> payload) {
    emit(
      jsonEncode(<String, Object?>{
        'type': type,
        'seq': 1,
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  /// Closes the channel.
  Future<void> closeChannel() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// The sink of a [FakeWebSocketChannel].
final class FakeWebSocketSink implements WebSocketSink {
  /// Creates a sink writing to [frames].
  FakeWebSocketSink(this.frames);

  /// The frames written by the client.
  final List<Object?> frames;

  @override
  void add(dynamic data) {
    frames.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();
}
