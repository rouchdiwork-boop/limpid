import 'dart:typed_data';

import 'auth/jwt_verifier.dart';
import 'auth/two_factor_guard.dart';
import 'db/account_purge_store.dart';
import 'db/admin_database.dart';
import 'db/audit_log.dart';
import 'db/book_sale_store.dart';
import 'db/bundle_record.dart';
import 'db/comment_store.dart';
import 'db/entitlement_store.dart';
import 'db/export_job_store.dart';
import 'db/kdp_database.dart';
import 'db/kdp_deposit_store.dart';
import 'db/project_store.dart';
import 'db/promo_code_store.dart';
import 'db/quota_database.dart';
import 'db/share_store.dart';
import 'db/stripe_event_database.dart';
import 'db/sync_store.dart';
import 'db/team_database.dart';
import 'db/two_factor_database.dart';
import 'db/webhook_database.dart';
import 'errors/app_exception.dart';
import 'logging/logger.dart';
import 'redis/key_value_store.dart';
import 'services/ai_consent_service.dart';
import 'services/ai_gateway.dart';
import 'services/feature_flag_service.dart';
import 'services/idempotency_service.dart';
import 'services/kdp_gateway.dart';
import 'services/payment_gateway.dart';
import 'services/sync_hub.dart';
import 'services/two_factor_service.dart';
import 'services/webhook_dispatcher.dart';
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
    this.quotas,
    this.twoFactor,
    this.teams,
    this.admin,
    this.webhooks,
    this.kdp,
    this.kdpDeposits,
    this.kdpGateway,
    this.stripeEvents,
    this.webhookDispatcher,
    this.featureFlags,
    this.shares,
    this.bookSales,
    this.entitlements,
    this.promoCodes,
    this.exportJobs,
    this.aiConsents,
    this.bundles,
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

  /// The plans and the quota counters of the accounts, when the feature is
  /// configured.
  ///
  /// The port is optional: a server without it serves the routes of the
  /// other features, and the routes of the quotas simply do not exist.
  final QuotaDatabase? quotas;

  /// The second factor of the accounts, when the feature is configured.
  final TwoFactorDatabase? twoFactor;

  /// The teams of the accounts, when the feature is configured.
  final TeamDatabase? teams;

  /// The back-office of the service, when the feature is configured.
  final AdminDatabase? admin;

  /// The API keys and the webhooks of the accounts, when the feature is
  /// configured.
  final WebhookDatabase? webhooks;

  /// The read-only shares of the books, when the feature is configured.
  ///
  /// The port is optional : a server qui ne partage pas de livre ne sert
  /// pas les routes de partage, plutot que de les servir en erreur.
  final ShareStore? shares;

  /// The prices of the books for sale, when the feature is configured.
  final BookSaleStore? bookSales;

  /// The rights of reading bought by the authors, when the feature is
  /// configured.
  final EntitlementStore? entitlements;

  /// The discount codes, when the feature is configured.
  final PromoCodeStore? promoCodes;

  /// The export jobs, when the feature is configured.
  ///
  /// The port is optional : a server qui n'exporte pas de livre ne sert
  /// pas les routes d'export, plutot que de les servir en erreur.
  final ExportJobStore? exportJobs;

  /// The bundles of the books, when the feature is configured.
  final BundleStore? bundles;

  /// The consent of the accounts to send their text to a third party.
  ///
  /// The service is optional : un serveur qui ne controle pas l'envoi
  /// refuse l'assistant plutot que de laisser partir le texte.
  final AiConsentService? aiConsents;

  /// The Amazon KDP publications, when the feature is configured.
  final KdpDatabase? kdp;

  /// The traces of the deposits at Amazon KDP, when the feature is
  /// configured.
  ///
  /// The port is optional, like the publications themselves: a server that
  /// does not distribute on Amazon serves the preparation of a publication
  /// and nothing more.
  final KdpDepositStore? kdpDeposits;

  /// The Stripe events already treated, when the feature is configured.
  ///
  /// The port is optional: a server without it does not receive the
  /// callbacks of the payment provider, and no formula is ever attributed
  /// by a client.
  final StripeEventDatabase? stripeEvents;

  /// The channel that deposits a package at Amazon KDP.
  ///
  /// It is optional, and the implementation that stands for a server
  /// without Amazon credentials says so instead of pretending that the
  /// book reached Amazon.
  final KdpGateway? kdpGateway;

  /// The dispatcher of the outgoing webhooks.
  ///
  /// It is shared: the modules that publish an event — a publication, an
  /// export, a plan change — use the same dispatcher, so a delivery is
  /// written in one place.
  final WebhookDispatcher? webhookDispatcher;

  /// The feature flags of the back-office, `null` when the back-office is
  /// not wired.
  ///
  /// A flag whose key is a plan capability is a **kill switch**: it cuts
  /// that capability for every account, without a redeployment.
  final FeatureFlagService? featureFlags;

  /// The plan of [userId], `null` when the account has none.
  ///
  /// The plan of an account without one is the free plan: the quota
  /// service applies it, not the base. The lookup is the single place
  /// where the services that need a plan — the teams, the second factor —
  /// read it, so they never depend on the quotas port.
  Future<String?> planOf(String userId) async {
    final AccountPlan? plan = await quotas?.planOf(userId);
    return plan?.plan.name;
  }

  /// The control of the second factor, `null` when it is not configured.
  ///
  /// The guard is built here, and not in the server, so that every entry
  /// point that authenticates a caller — the HTTP routes **and** the real
  /// time relay — applies the same control.
  TwoFactorGuard? get twoFactorGuard {
    final TwoFactorDatabase? database = twoFactor;
    if (database == null) return null;
    return TwoFactorService(database: database, planOf: planOf);
  }

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
  Future<void> ensureConsent({required String userId}) async {
    // Aucun fournisseur n'est configure : il n'y a rien a envoyer, et
    // l'appel est refuse de toute facon.
    throw _notConfigured();
  }

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
