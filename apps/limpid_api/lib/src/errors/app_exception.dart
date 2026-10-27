/// Stable, technical error codes shared by every route.
///
/// The codes are part of the public API contract (ARCHITECTURE.md §6.4):
/// they never change wording and never carry a user-facing sentence. The
/// `message` of an error is written in French and is meant for the author.
library;

/// Stable error codes.
abstract final class ErrorCodes {
  /// The token is missing, malformed or otherwise invalid.
  static const String unauthorized = 'unauthorized';

  /// The token is well formed but its validity period has passed.
  static const String tokenExpired = 'token_expired';

  /// The role of the user is not sufficient for the operation.
  static const String forbidden = 'forbidden';

  /// The resource does not exist, or is hidden by data isolation.
  static const String notFound = 'not_found';

  /// A business conflict (plan, state, busy resource).
  static const String conflict = 'conflict';

  /// An idempotency key was reused with a different body.
  static const String idempotencyKeyConflict = 'idempotency_key_conflict';

  /// The sync protocol version of the client is not supported.
  static const String schemaVersionUnsupported = 'schema_version_unsupported';

  /// The client is ahead of the server protocol version.
  static const String clientAhead = 'client_ahead';

  /// The request body exceeds the accepted limit.
  static const String payloadTooLarge = 'payload_too_large';

  /// The input schema validation failed.
  static const String validationFailed = 'validation_failed';

  /// The feature quota of the account is exhausted.
  static const String quotaExceeded = 'quota_exceeded';

  /// The request rate limit was exceeded.
  static const String rateLimited = 'rate_limited';

  /// The operation requires a higher plan.
  static const String planLimitReached = 'plan_limit_reached';

  /// The AI provider is unavailable or saturated.
  static const String aiProviderUnavailable = 'ai_provider_unavailable';

  /// L'auteur n'a pas autorisé l'envoi de son texte à un tiers.
  static const String aiConsentRequired = 'ai_consent_required';

  /// The export generator failed; the operation can be retried.
  static const String exportFailed = 'export_failed';

  /// An unexpected error, logged with its context.
  static const String internalError = 'internal_error';

  /// The route does not exist.
  static const String routeNotFound = 'route_not_found';

  /// The request timed out.
  static const String requestTimeout = 'request_timeout';
}

/// Base class of every error the API converts into an HTTP response.
///
/// An [AppException] carries a stable [code], a French [message] intended for
/// the author, an optional HTTP [statusCode] and optional [details] that
/// describe the failure without leaking server internals.
sealed class AppException implements Exception {
  /// Creates an application exception.
  const AppException({
    required this.code,
    required this.statusCode,
    required this.message,
    this.details = const <String, Object?>{},
    this.cause,
  });

  /// The stable, technical error code.
  final String code;

  /// The user facing message, in French.
  final String message;

  /// The HTTP status code to answer with.
  final int statusCode;

  /// Machine readable details about the failure.
  final Map<String, Object?> details;

  /// The original error, kept for the server side log only.
  final Object? cause;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// The request carries no usable authentication token.
final class UnauthorizedException extends AppException {
  /// Creates an unauthorized error.
  const UnauthorizedException({
    super.message = "Votre session n'est pas valide. Reconnectez-vous.",
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.unauthorized, statusCode: 401);
}

/// The authentication token is valid but expired.
final class TokenExpiredException extends AppException {
  /// Creates a token-expired error.
  const TokenExpiredException({
    super.message = 'Votre session a expiré. Reconnectez-vous pour continuer.',
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.tokenExpired, statusCode: 401);
}

/// The role of the user does not allow the operation.
final class ForbiddenException extends AppException {
  /// Creates a forbidden error.
  const ForbiddenException({
    super.message = "Vous n'avez pas les droits nécessaires pour cette action.",
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.forbidden, statusCode: 403);
}

/// The resource does not exist or is hidden by isolation.
final class NotFoundException extends AppException {
  /// Creates a not-found error.
  const NotFoundException({
    super.message = "Cette ressource n'existe pas ou n'est plus accessible.",
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.notFound, statusCode: 404);
}

/// The input did not satisfy the request schema.
final class ValidationException extends AppException {
  /// Creates a validation error.
  ///
  /// [field] names the faulty input so the message can point at it.
  const ValidationException({
    required this.field,
    required super.message,
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.validationFailed, statusCode: 400);

  /// The name of the faulty field.
  final String field;
}

/// A business conflict occurred.
final class ConflictException extends AppException {
  /// Creates a conflict error.
  const ConflictException({
    required super.message,
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.conflict, statusCode: 409);
}

/// The idempotency key was reused with a different body.
final class IdempotencyKeyConflictException extends AppException {
  /// Creates an idempotency conflict error.
  const IdempotencyKeyConflictException({
    super.message =
        'Cette clé d\'idempotence a déjà été utilisée avec un autre contenu.',
  }) : super(code: ErrorCodes.idempotencyKeyConflict, statusCode: 409);
}

/// The sync protocol version carried by the client is refused.
final class SchemaVersionException extends AppException {
  /// Creates a schema version error.
  const SchemaVersionException({
    required super.message,
    required this.clientVersion,
    required this.minSupported,
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.schemaVersionUnsupported, statusCode: 409);

  /// The version carried by the client.
  final int clientVersion;

  /// The oldest version the server still accepts.
  final int minSupported;
}

/// The client is ahead of the server protocol version.
final class ClientAheadException extends AppException {
  /// Creates a client-ahead error.
  const ClientAheadException({
    required super.message,
    required this.clientVersion,
    required this.serverVersion,
  }) : super(code: ErrorCodes.clientAhead, statusCode: 426);

  /// The version carried by the client.
  final int clientVersion;

  /// The version supported by the server.
  final int serverVersion;
}

/// The request body is larger than the accepted limit.
final class PayloadTooLargeException extends AppException {
  /// Creates a payload-too-large error.
  const PayloadTooLargeException({
    required super.message,
    required this.limitBytes,
  }) : super(code: ErrorCodes.payloadTooLarge, statusCode: 413);

  /// The maximum accepted body size, in bytes.
  final int limitBytes;
}

/// The rate limit of the caller has been exceeded.
final class RateLimitedException extends AppException {
  /// Creates a rate-limit error.
  const RateLimitedException({
    required super.message,
    required this.retryAfterSeconds,
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.rateLimited, statusCode: 429);

  /// How long the caller should wait before retrying, in seconds.
  final int retryAfterSeconds;
}

/// The quota of the account is exhausted.
final class QuotaExceededException extends AppException {
  /// Creates a quota error.
  const QuotaExceededException({
    required super.message,
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.quotaExceeded, statusCode: 429);
}

/// The operation requires a higher plan.
final class PlanLimitException extends AppException {
  /// Creates a plan-limit error.
  ///
  /// [details] names the feature at fault: the quota guard describes the
  /// limit it reached and the consumption it compared it to.
  const PlanLimitException({
    super.message =
        "Cette fonctionnalité n'est pas incluse dans votre formule. "
        'Passez à la formule supérieure pour y accéder.',
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.planLimitReached, statusCode: 402);
}

/// The AI provider is unavailable or saturated.
final class AiProviderUnavailableException extends AppException {
  /// Creates an AI provider error.
  const AiProviderUnavailableException({
    required super.message,
    super.details = const <String, Object?>{},
    super.cause,
  }) : super(code: ErrorCodes.aiProviderUnavailable, statusCode: 503);
}

/// L'auteur n'a pas autorisé l'envoi de son texte à un tiers.
///
/// Le refus dit ce qu'il faut faire, et il ne dit rien du compte : le
/// message ne divulgue ni l'identifiant du compte, ni son adresse, ni ce
/// qu'il a écrit.
final class AiConsentRequiredException extends AppException {
  /// Crée un refus de consentement.
  const AiConsentRequiredException({
    super.message =
        "L'envoi de votre texte à un fournisseur externe n'est pas "
        'autorisé. Activez cette option dans vos réglages pour utiliser '
        "l'assistant.",
    super.details = const <String, Object?>{},
  }) : super(code: ErrorCodes.aiConsentRequired, statusCode: 403);
}

/// The export generator failed; the operation can be retried.
final class ExportFailedException extends AppException {
  /// Creates an export error.
  const ExportFailedException({
    required super.message,
    super.details = const <String, Object?>{},
    super.cause,
  }) : super(code: ErrorCodes.exportFailed, statusCode: 500);
}

/// The request exceeded the server side time budget.
final class RequestTimeoutException extends AppException {
  /// Creates a timeout error.
  const RequestTimeoutException({
    required super.message,
    required this.timeoutSeconds,
  }) : super(code: ErrorCodes.requestTimeout, statusCode: 504);

  /// The time budget of the request, in seconds.
  final int timeoutSeconds;
}

/// An unexpected error, always logged with its context.
final class InternalException extends AppException {
  /// Creates an internal error.
  const InternalException({
    required super.message,
    super.details = const <String, Object?>{},
    super.cause,
  }) : super(code: ErrorCodes.internalError, statusCode: 500);
}

/// A dependency of the service is unreachable.
final class ServiceUnavailableException extends AppException {
  /// Creates a service-unavailable error.
  const ServiceUnavailableException({
    required super.message,
    super.details = const <String, Object?>{},
  }) : super(code: 'service_unavailable', statusCode: 503);
}

/// The payment provider refused a request.
final class PaymentException extends AppException {
  /// Creates a payment error.
  const PaymentException({
    required super.message,
    super.details = const <String, Object?>{},
    super.cause,
  }) : super(code: 'payment_failed', statusCode: 502);
}

/// The configuration of the server is invalid.
final class ConfigException extends AppException {
  /// Creates a configuration error.
  ///
  /// [variable] names the environment variable at fault.
  const ConfigException({required this.variable, required super.message})
    : super(code: 'config_invalid', statusCode: 500);

  /// The environment variable at fault.
  final String variable;
}
