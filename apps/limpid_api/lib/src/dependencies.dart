import 'dart:typed_data';

import 'auth/jwt_verifier.dart';
import 'db/account_purge_store.dart';
import 'db/audit_log.dart';
import 'db/comment_store.dart';
import 'db/project_store.dart';
import 'db/sync_store.dart';
import 'errors/app_exception.dart';
import 'logging/logger.dart';
import 'redis/key_value_store.dart';
import 'services/ai_gateway.dart';
import 'services/idempotency_service.dart';
import 'services/payment_gateway.dart';
import 'services/sync_hub.dart';
import 'storage/object_storage.dart';

/// A probe telling whether a dependency answers.
abstract interface class HealthProbe {
  /// Whether the dependency is reachable.
  Future<bool> ping();
}

/// A probe that always answers: used by the test suite.
final class AlwaysHealthyProbe implements HealthProbe {
  /// Creates a probe.
  const AlwaysHealthyProbe();

  @override
  Future<bool> ping() async => true;
}

/// The dependencies of the API.
///
/// The routes only depend on the interfaces exposed here, which lets the
/// test suite run the whole server without any external service.
final class AppDependencies {
  /// Creates the dependencies.
  const AppDependencies({
    required this.projects,
    required this.sync,
    required this.audit,
    required this.comments,
    required this.purge,
    required this.ai,
    required this.payments,
    required this.storage,
    required this.keyValue,
    required this.jwtVerifier,
    required this.logger,
    required this.databaseProbe,
    required this.syncHub,
    required this.shutdown,
  });

  /// The projects of the callers.
  final ProjectStore projects;

  /// The sync journal of the projects.
  final SyncStore sync;

  /// The audit journal.
  final AuditLog audit;

  /// The store that erases the data of the purged accounts.
  final AccountPurgeStore purge;

  /// The discussions of the projects.
  final CommentStore comments;

  /// The AI capability.
  final AiGateway ai;

  /// The payment capability.
  final PaymentGateway payments;

  /// The storage of the exported artefacts.
  final ObjectStorage storage;

  /// The short lived key/value store.
  final KeyValueStore keyValue;

  /// The verifier of the authentication tokens.
  final JwtVerifier jwtVerifier;

  /// The structured logger.
  final Logger logger;

  /// The probe of the database.
  final HealthProbe databaseProbe;

  /// The relay of the real time operations.
  final SyncHub syncHub;

  /// The callback releasing the resources held by the dependencies.
  final Future<void> Function() shutdown;

  /// The service guarding the calls with a side effect.
  IdempotencyService get idempotency => IdempotencyService(store: keyValue);

  /// Releases the resources held by the dependencies.
  ///
  /// The server calls it once the last request is served: the database
  /// connection is closed and the migrations of the next boot are applied on
  /// a consistent file.
  Future<void> close() => shutdown();
}

/// A [KeyValueStore] standing for a Redis that is not configured.
///
/// The development profile may run without Redis. The cache and the
/// idempotency keys are then unavailable, and every call answers a clean
/// error instead of crashing the server.
final class DisabledKeyValueStore implements KeyValueStore {
  /// Creates a store.
  const DisabledKeyValueStore();

  @override
  Future<void> set(String key, String value, {Duration? ttl}) =>
      throw _notConfigured();

  @override
  Future<String?> get(String key) => throw _notConfigured();

  @override
  Future<void> delete(String key) => throw _notConfigured();

  @override
  Future<bool> ping() async => false;

  static ServiceUnavailableException _notConfigured() {
    return const ServiceUnavailableException(
      message:
          'Redis n\'est pas configuré sur ce poste : le cache et la file '
          'd\'attente sont indisponibles.',
    );
  }
}

/// An [AiGateway] standing for an AI provider that is not configured.
///
/// The routes needing the provider answer a clean error instead of crashing
/// the server.
final class UnavailableAiGateway implements AiGateway {
  /// Creates a gateway.
  const UnavailableAiGateway();

  @override
  Stream<AiEvent> generate(AiGenerateRequest request) => throw _notConfigured();

  @override
  Stream<AiEvent> inline(AiInlineRequest request) => throw _notConfigured();

  @override
  Stream<AiEvent> query(AiQueryRequest request) => throw _notConfigured();

  static ServiceUnavailableException _notConfigured() {
    return const ServiceUnavailableException(
      message:
          'Le fournisseur d\'IA n\'est pas configuré sur ce poste : '
          'la génération est indisponible.',
    );
  }
}

/// A [PaymentGateway] standing for a payment provider that is not
/// configured.
final class UnavailablePaymentGateway implements PaymentGateway {
  /// Creates a gateway.
  const UnavailablePaymentGateway();

  @override
  Future<CheckoutSession> createSession(CheckoutRequest request) =>
      throw _notConfigured();

  @override
  Future<CheckoutSession?> retrieveSession(String sessionId) =>
      throw _notConfigured();

  static ServiceUnavailableException _notConfigured() {
    return const ServiceUnavailableException(
      message:
          'Le prestataire de paiement n\'est pas configuré sur ce poste : '
          'la commande est indisponible.',
    );
  }
}

/// An [ObjectStorage] standing for a remote storage that is not configured.
final class UnavailableObjectStorage implements ObjectStorage {
  /// Creates a storage.
  const UnavailableObjectStorage();

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) => throw _notConfigured();

  @override
  Future<String> presignedUrl({
    required String key,
    required Duration expires,
  }) => throw _notConfigured();

  static ServiceUnavailableException _notConfigured() {
    return const ServiceUnavailableException(
      message:
          'Le stockage distant n\'est pas configuré sur ce poste : '
          'l\'export est indisponible.',
    );
  }
}
