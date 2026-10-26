import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The error raised when the Redis server answers with an error reply.
final class RedisException implements Exception {
  /// Creates a Redis error.
  const RedisException(this.message);

  /// The message of the error reply.
  final String message;

  @override
  String toString() => 'RedisException($message)';
}

/// Raised internally when the buffer does not hold a complete reply yet.
final class _IncompleteReply implements Exception {
  const _IncompleteReply();
}

/// A minimal Redis client speaking RESP2 over TCP.
///
/// The client implements the commands the API needs (`AUTH`, `PING`, `GET`,
/// `SET`, `DEL`) and nothing more. It exists because the `redis` package
/// published on pub.dev declares `sdk: ">=2.12.0 <4.0.0"` and therefore
/// cannot be resolved on the Dart 3.12 SDK this API targets.
final class RedisClient {
  RedisClient._(this._socket, this._host, this._port);

  /// Connects to the Redis server described by [url].
  ///
  /// The url follows the usual `redis://[:password@]host:port/database`
  /// shape; the `rediss` scheme opens a TLS socket.
  static Future<RedisClient> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final Uri uri = Uri.parse(url);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'Expected a redis:// connection string',
      );
    }
    final int port = uri.hasPort ? uri.port : 6379;
    final bool secure = uri.scheme == 'rediss';
    final Socket socket = secure
        ? await SecureSocket.connect(uri.host, port, timeout: timeout)
        : await Socket.connect(uri.host, port, timeout: timeout);

    final RedisClient client = RedisClient._(socket, uri.host, port);
    socket.listen(
      client._onData,
      onError: client._onError,
      onDone: client._onDone,
      cancelOnError: false,
    );

    final String? password = _passwordOf(uri);
    if (password != null && password.isNotEmpty) {
      await client.command(<String>['AUTH', password]);
    }
    return client;
  }

  static String? _passwordOf(Uri uri) {
    if (uri.userInfo.isEmpty) return null;
    final List<String> credentials = uri.userInfo.split(':');
    return credentials.length > 1 ? credentials.sublist(1).join(':') : null;
  }

  final Socket _socket;
  final String _host;
  final int _port;

  final List<int> _buffer = <int>[];
  Completer<Object?>? _pending;
  Object? _failure;

  /// The host of the server.
  String get host => _host;

  /// The port of the server.
  int get port => _port;

  /// Sends a command and returns its reply.
  Future<Object?> command(List<String> arguments) async {
    if (arguments.isEmpty) {
      throw ArgumentError.value(arguments, 'arguments', 'Expected a command');
    }
    final Object? failure = _failure;
    if (failure != null) throw failure;
    if (_pending != null) {
      throw const RedisException(
        'Only one command can be in flight at a time.',
      );
    }

    final Completer<Object?> completer = Completer<Object?>();
    _pending = completer;
    try {
      _socket.add(encodeCommand(arguments));
    } on Object catch (error) {
      _pending = null;
      throw RedisException('The command could not be sent: $error');
    }
    return completer.future;
  }

  /// Closes the connection.
  Future<void> close() async {
    await _socket.close();
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _drain();
  }

  void _onError(Object error) {
    _fail(RedisException('The connection failed: $error'));
  }

  void _onDone() {
    _fail(const RedisException('The connection was closed by the server.'));
  }

  void _fail(Object error) {
    _failure = error;
    final Completer<Object?>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  void _drain() {
    final Completer<Object?>? pending = _pending;
    if (pending == null) return;
    final RespReply? decoded = decodeReply(_buffer);
    if (decoded == null) return;
    _buffer.removeRange(0, decoded.consumed);
    _pending = null;
    if (decoded.error != null) {
      pending.completeError(RedisException(decoded.error!));
      return;
    }
    pending.complete(decoded.value);
  }

  /// Encodes a command as a RESP2 array of bulk strings.
  static Uint8List encodeCommand(List<String> arguments) {
    final BytesBuilder builder = BytesBuilder();
    builder.add('*${arguments.length}\r\n'.codeUnits);
    for (final String argument in arguments) {
      final List<int> bytes = utf8.encode(argument);
      builder.add('\$${bytes.length}\r\n'.codeUnits);
      builder.add(bytes);
      builder.add('\r\n'.codeUnits);
    }
    return builder.toBytes();
  }
}

/// The decoded content of a RESP2 reply.
final class RespReply {
  const RespReply({required this.value, required this.consumed, this.error});

  final Object? value;
  final int consumed;
  final String? error;
}

/// Decodes a RESP2 reply from [bytes].
///
/// Returns `null` when the buffer does not hold a complete reply yet.
RespReply? decodeReply(List<int> bytes) {
  final _Reader reader = _Reader(bytes);
  try {
    final Object? value = reader.readValue();
    if (value is _ErrorReply) {
      return RespReply(
        value: null,
        consumed: reader.offset,
        error: value.message,
      );
    }
    return RespReply(value: value, consumed: reader.offset);
  } on _IncompleteReply {
    return null;
  }
}

/// A reader over the raw bytes of a RESP2 reply.
final class _Reader {
  _Reader(this.bytes);

  final List<int> bytes;
  int offset = 0;

  Object? readValue() {
    if (offset >= bytes.length) throw const _IncompleteReply();
    final int marker = bytes[offset];
    switch (marker) {
      case 0x2b:
        return _readSimpleString();
      case 0x2d:
        return _readError();
      case 0x3a:
        return _readInteger();
      case 0x24:
        return _readBulkString();
      case 0x2a:
        return _readArray();
      default:
        throw RedisException(
          'Unknown RESP marker 0x${marker.toRadixString(16)}.',
        );
    }
  }

  String _readLine() {
    final int index = _indexOfCrlf();
    if (index < 0) throw const _IncompleteReply();
    final String line = utf8.decode(bytes.sublist(offset, index));
    offset = index + 2;
    return line;
  }

  int _indexOfCrlf() {
    for (var i = offset; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x0d && bytes[i + 1] == 0x0a) return i;
    }
    return -1;
  }

  Object? _readSimpleString() {
    offset += 1;
    return _readLine();
  }

  Object? _readError() {
    offset += 1;
    return _ErrorReply(_readLine());
  }

  Object? _readInteger() {
    offset += 1;
    final String line = _readLine();
    final int? value = int.tryParse(line);
    if (value == null) throw RedisException('Invalid integer "$line".');
    return value;
  }

  Object? _readBulkString() {
    offset += 1;
    final String header = _readLine();
    final int? length = int.tryParse(header);
    if (length == null) {
      throw RedisException('Invalid bulk string length "$header".');
    }
    if (length < 0) return null;
    if (offset + length + 2 > bytes.length) throw const _IncompleteReply();
    final String value = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length + 2;
    return value;
  }

  Object? _readArray() {
    offset += 1;
    final String header = _readLine();
    final int? length = int.tryParse(header);
    if (length == null) {
      throw RedisException('Invalid array length "$header".');
    }
    if (length < 0) return null;
    final List<Object?> items = <Object?>[];
    for (var i = 0; i < length; i++) {
      items.add(readValue());
    }
    return items;
  }
}

/// An error reply of the Redis protocol.
final class _ErrorReply {
  const _ErrorReply(this.message);

  final String message;
}
