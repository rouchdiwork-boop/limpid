import 'dart:convert';

/// The codec shared by the SQLite adapters.
///
/// The dialect of the development database differs from the one of Postgres
/// on three points, and this file is the single place where the difference
/// is spelled out:
///
/// - a timestamp is an `INTEGER` counting the **microseconds since the Unix
///   epoch, in UTC**. An integer sorts exactly like a `TIMESTAMPTZ` and
///   keeps the microsecond resolution of Dart's `DateTime`, which a textual
///   ISO 8601 column would lose;
/// - a boolean is an `INTEGER` holding `0` or `1`;
/// - a JSON document is a `TEXT` holding the JSON encoding of the document.
abstract final class SqliteValues {
  /// Encodes a timestamp as microseconds since the Unix epoch.
  static int encodeTimestamp(DateTime value) =>
      value.toUtc().microsecondsSinceEpoch;

  /// Decodes a timestamp stored as microseconds since the Unix epoch.
  ///
  /// The textual ISO 8601 form is accepted as well, so a row written by
  /// hand stays readable.
  static DateTime decodeTimestamp(Object? value) {
    if (value is int) {
      return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
    }
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }

  /// Decodes a timestamp that may be absent.
  static DateTime? decodeNullableTimestamp(Object? value) {
    if (value == null) return null;
    return decodeTimestamp(value);
  }

  /// Encodes a boolean as `0` or `1`.
  static int encodeBoolean(bool value) => value ? 1 : 0;

  /// Decodes a boolean stored as `0` or `1`.
  static bool decodeBoolean(Object? value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  /// Encodes a JSON document as its textual form.
  static String encodeJson(Map<String, Object?> value) => jsonEncode(value);

  /// Decodes a JSON document stored as its textual form.
  ///
  /// A malformed or absent document decodes to an empty map, the same way the
  /// Postgres adapter reads an empty `JSONB`.
  static Map<String, dynamic> decodeJson(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      final Object? decoded = _tryDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const <String, dynamic>{};
  }

  /// Decodes an integer column.
  static int decodeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
