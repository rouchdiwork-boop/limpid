/// The errors raised by the local data layer.
///
/// The layer never swallows an error and never lets a raw exception escape:
/// every failure is turned into one of the types below, so the caller can
/// react precisely (retry, re-authenticate, show a message…).
library;

/// The base class of every error raised by the local database.
sealed class LocalDataException implements Exception {
  /// Creates an error.
  const LocalDataException(this.message, {this.cause});

  /// A human readable explanation, safe to log.
  final String message;

  /// The original error, when the failure wraps one.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The local database could not be opened.
///
/// The web build is the usual cause: Drift needs the SQLite WebAssembly
/// module and its worker, and neither can be produced by the application
/// alone.
final class LocalDatabaseUnavailableException extends LocalDataException {
  /// Creates an error.
  const LocalDatabaseUnavailableException(super.message, {super.cause});
}

/// A record the caller asked for does not exist.
final class LocalRecordNotFoundException extends LocalDataException {
  /// Creates an error.
  const LocalRecordNotFoundException(super.message);
}

/// A chapter or a scene could not be attached to a project.
///
/// The contract of the repository does not carry the parent of a chapter: the
/// link is resolved from the project that already lists it, and the error is
/// raised when the link is ambiguous.
final class LocalAmbiguousParentException extends LocalDataException {
  /// Creates an error.
  const LocalAmbiguousParentException(super.message);
}

/// The base class of every error raised by the API client.
sealed class ApiException implements Exception {
  /// Creates an error.
  const ApiException(this.message, {this.code, this.statusCode, this.cause});

  /// A human readable explanation, safe to log.
  final String message;

  /// The stable, technical code returned by the server, when it sent one.
  final String? code;

  /// The HTTP status returned by the server, `null` when the request never
  /// reached it.
  final int? statusCode;

  /// The original error, when the failure wraps one.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType($code${statusCode == null ? '' : ', $statusCode'}): '
      '$message';
}

/// The API could not be reached: no route to host, DNS failure…
final class ApiNetworkException extends ApiException {
  /// Creates an error.
  const ApiNetworkException(super.message, {super.code, super.cause});
}

/// The API did not answer before the deadline.
final class ApiTimeoutException extends ApiException {
  /// Creates an error.
  const ApiTimeoutException(super.message, {super.code, super.cause});
}

/// The API refused the credentials of the client.
final class ApiUnauthorizedException extends ApiException {
  /// Creates an error.
  const ApiUnauthorizedException(super.message, {super.code, super.statusCode});
}

/// The resource does not exist.
final class ApiNotFoundException extends ApiException {
  /// Creates an error.
  const ApiNotFoundException(super.message, {super.code, super.statusCode});
}

/// The API refused the request: the payload is invalid.
final class ApiValidationException extends ApiException {
  /// Creates an error.
  const ApiValidationException(super.message, {super.code, super.statusCode});
}

/// The API answered an error status the client cannot fix.
final class ApiServerException extends ApiException {
  /// Creates an error.
  const ApiServerException(super.message, {super.code, super.statusCode});
}

/// The answer of the API is not the payload the client expects.
final class ApiMalformedResponseException extends ApiException {
  /// Creates an error.
  const ApiMalformedResponseException(
    super.message, {
    super.code,
    super.statusCode,
    super.cause,
  });
}
