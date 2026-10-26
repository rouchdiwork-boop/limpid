/// Base class for every error raised by `limpid_core`.
///
/// Errors are never swallowed: callers are expected to catch these typed
/// exceptions and surface them with a user-facing message.
sealed class LimpidCoreException implements Exception {
  /// Creates an exception with a stable technical [code] and a [message].
  const LimpidCoreException(this.message, {this.code = 'limpid_error'});

  /// Stable, technical, translatable error code.
  final String code;

  /// Human readable explanation, safe to log.
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Raised when block content cannot be parsed or violates its invariants.
final class InvalidContentException extends LimpidCoreException {
  /// Creates an invalid-content error.
  const InvalidContentException(
    super.message, {
    super.code = 'invalid_content',
  });
}

/// Raised when a sync operation is malformed or cannot be applied.
final class InvalidSyncOperationException extends LimpidCoreException {
  /// Creates an invalid-operation error.
  const InvalidSyncOperationException(
    super.message, {
    super.code = 'invalid_sync_operation',
  });
}

/// Raised when a document invariant is violated (unknown parent, cycle…).
final class InvalidDocumentException extends LimpidCoreException {
  /// Creates an invalid-document error.
  const InvalidDocumentException(
    super.message, {
    super.code = 'invalid_document',
  });
}
