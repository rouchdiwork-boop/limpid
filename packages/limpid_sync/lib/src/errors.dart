import 'package:limpid_sync/src/conflict.dart';

/// Base class of every error raised by `limpid_sync`.
///
/// Errors are never swallowed silently: the sync client turns them into a
/// [SyncStatus.error] state and publishes them on its event stream, and the
/// typed subclasses below let the caller react precisely (re-authenticate,
/// surface a conflict, retry later…).
sealed class SyncException implements Exception {
  /// Creates a sync error with a stable technical [code] and a [message].
  const SyncException(this.message, {this.code = 'sync_error'});

  /// Stable, technical, translatable error code.
  final String code;

  /// Human readable explanation, safe to log.
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Raised when the API cannot be reached, answers an error status, or
/// returns a payload the client cannot decode.
final class SyncTransportException extends SyncException {
  /// Creates a transport error.
  const SyncTransportException(
    super.message, {
    super.code = 'sync_transport_error',
    this.statusCode,
    this.isNetworkFailure = false,
    this.cause,
  });

  /// The HTTP status returned by the API, `null` when the request never
  /// reached the server.
  final int? statusCode;

  /// Whether the failure is a connectivity problem (no route to host, DNS
  /// failure, timeout) rather than a server-side rejection.
  ///
  /// The sync client uses this flag to switch to the `offline` status
  /// instead of the `error` one.
  final bool isNetworkFailure;

  /// The original error, when the failure wraps one.
  final Object? cause;
}

/// Raised when the API rejects the credentials of the client.
final class SyncAuthException extends SyncException {
  /// Creates an authentication error.
  const SyncAuthException(super.message, {super.code = 'sync_unauthorized'});
}

/// Raised when the client detects divergences the author must arbitrate.
final class SyncConflictException extends SyncException {
  /// Creates a conflict error.
  const SyncConflictException(
    super.message, {
    required this.reports,
    super.code = 'sync_conflict',
  });

  /// The divergences that triggered the error.
  final List<ConflictReport> reports;
}
