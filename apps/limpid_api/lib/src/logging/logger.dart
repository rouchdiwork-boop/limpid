import 'dart:convert';

import '../config/app_config.dart';

/// Keys that must never reach the logs, whatever the caller passes.
const Set<String> _redactedKeys = <String>{
  'authorization',
  'body',
  'content',
  'cookie',
  'email',
  'jwt',
  'password',
  'payload',
  'prompt',
  'secret',
  'set-cookie',
  'text',
  'token',
};

/// Maximum length of a free-form value written to the logs.
const int _maxValueLength = 512;

/// A structured JSON logger writing one JSON object per line on stdout.
///
/// The logger never writes a request body, a book text, a key or a token:
/// sensitive fields are dropped and long values are truncated.
final class Logger {
  /// Creates a logger.
  ///
  /// [sink] receives the serialized lines; it defaults to stdout.
  Logger({required this.level, void Function(String line)? sink})
    : _sink = sink ?? stdoutSink;

  /// The default sink: standard output.
  static void stdoutSink(String line) {
    // ignore: avoid_print
    print(line);
  }

  /// The minimum level of the emitted records.
  final LogLevel level;

  final void Function(String line) _sink;

  /// Writes a debug record.
  void debug(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.debug, message, fields);

  /// Writes an informational record.
  void info(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.info, message, fields);

  /// Writes a warning record.
  void warning(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.warning, message, fields);

  /// Writes an error record.
  void error(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.error, message, fields);

  /// Writes a record when [level] is at least the configured level.
  void log(
    LogLevel level,
    String message, [
    Map<String, Object?> fields = const {},
  ]) {
    if (level.index < this.level.index) return;
    final Map<String, Object?> record = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.label,
      'message': message,
      ...sanitize(fields),
    };
    _sink(jsonEncode(record));
  }

  /// Removes the sensitive entries of [fields] and truncates long values.
  static Map<String, Object?> sanitize(Map<String, Object?> fields) {
    final Map<String, Object?> safe = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in fields.entries) {
      final String key = entry.key.toLowerCase();
      if (_redactedKeys.contains(key)) continue;
      safe[entry.key] = _sanitizeValue(entry.value);
    }
    return safe;
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is int || value is double) {
      return value;
    }
    if (value is String) {
      if (value.length <= _maxValueLength) return value;
      return '${value.substring(0, _maxValueLength)}…';
    }
    if (value is Iterable) {
      return value.length.toString();
    }
    return value.runtimeType.toString();
  }
}
