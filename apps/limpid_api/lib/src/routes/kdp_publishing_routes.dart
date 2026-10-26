import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/kdp_deposit_record.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/kdp_publishing_service.dart';
import '../services/kdp_reconciliation.dart';

/// Enregistre les routes de dépôt du dossier Amazon KDP.
///
/// Les routes déposent le dossier préparé auprès d'Amazon et rendent la
/// trace du dépôt : l'identifiant du dépôt, son état, la date et le motif
/// d'un échec.
///
/// Le refus d'Amazon n'est pas une erreur technique : la route répond avec
/// la trace, dont la liste des problèmes se lit comme celle du contrôle de
/// soumission. Un serveur sans identifiants Amazon répond un refus propre,
/// qui dit que la distribution n'est pas configurée.
///
/// Les routes ne chevauchent pas celles de la préparation : le chemin de
/// lecture d'un dépôt porte deux segments, là où celui de la publication en
/// porte un.
///
/// La réconciliation d'un dépôt ambigu a sa propre route : elle ne parle
/// pas à Amazon, elle consigne ce que l'auteur déclare avoir vu dans la
/// console KDP d'Amazon.
void registerKdpPublishingRoutes(
  Router router,
  KdpPublishingService service,
  AppConfig config,
) {
  router.post('/v1/publishing/kdp/deposits', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    _requireConfigured(config);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String publicationId = body.requireString(
      'publication_id',
      maxLength: maxPublicationIdLength,
    );
    final KdpDeposit deposit = await service.deposit(
      auth: auth,
      publicationId: publicationId,
    );
    return ApiResponse.ok(deposit.toJson());
  });

  router.get('/v1/publishing/kdp/deposits', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final List<KdpDeposit> deposits = await service.list(auth: auth);
    return ApiResponse.ok(<Object?>[
      for (final KdpDeposit deposit in deposits) deposit.toJson(),
    ]);
  });

  router.get('/v1/publishing/kdp/deposits/<depositId>', (
    Request request,
    String depositId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final KdpDeposit? deposit = await service.find(
      auth: auth,
      depositId: depositId,
    );
    if (deposit == null) {
      throw const NotFoundException(
        message: "Ce dépôt n'existe pas ou n'est plus accessible.",
      );
    }
    return ApiResponse.ok(deposit.toJson());
  });

  // La réconciliation d'un dépôt dont l'issue est inconnue. Le dossier
  // n'est jamais relancé tout seul : seul l'auteur peut dire ce qui s'est
  // passé chez Amazon, et lui seul peut lever l'ambiguïté.
  //
  // La route ne demande pas la configuration d'Amazon : elle ne parle pas
  // à Amazon. Un auteur doit toujours pouvoir résoudre un dépôt ambigu,
  // même si le serveur a perdu ses identifiants entre-temps.
  router.post('/v1/publishing/kdp/deposits/<depositId>/reconciliation', (
    Request request,
    String depositId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    _requireDepositId(depositId);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final KdpDeposit deposit = await service.reconcile(
      auth: auth,
      depositId: depositId,
      reconciliation: _reconciliationOf(body),
    );
    return ApiResponse.ok(deposit.toJson());
  });
}

/// La déclaration de l'auteur lue dans le corps de la requête.
///
/// La déclaration est explicite : le corps doit dire ce qui s'est passé
/// chez Amazon, il ne peut pas le deviner.
KdpReconciliation _reconciliationOf(JsonBody body) {
  final String outcome = body.requireString('outcome');
  return switch (outcome) {
    'submitted' => KdpReconciliation(
      outcome: KdpReconciliationOutcome.submitted,
      amazonSubmissionId: body.requireString(
        'amazon_submission_id',
        maxLength: KdpPublishingService.maxAmazonSubmissionIdLength,
      ),
    ),
    'not_received' => const KdpReconciliation(
      outcome: KdpReconciliationOutcome.notReceived,
    ),
    _ => throw ValidationException(
      field: 'outcome',
      message:
          'Le champ « outcome » doit valoir « submitted » ou '
          '« not_received ».',
    ),
  };
}

/// Refuse un identifiant de dépôt qui n'a pas la forme attendue.
void _requireDepositId(String depositId) {
  if (depositId.length <= maxDepositIdLength) return;
  throw ValidationException(
    field: 'deposit_id',
    message:
        "L'identifiant du dépôt ne doit pas dépasser "
        '$maxDepositIdLength caractères.',
  );
}

/// Refuse la demande quand la distribution Amazon n'est pas configurée.
///
/// Un secret absent ne doit jamais faire tomber le serveur : la route
/// répond un refus propre, qui dit ce qu'il manque.
void _requireConfigured(AppConfig config) {
  if (config.hasKdpDistribution) return;
  throw const ServiceUnavailableException(
    message:
        "La distribution Amazon KDP n'est pas configurée sur ce serveur. "
        "L'administrateur doit renseigner les identifiants de l'intégration.",
  );
}

/// La longueur maximale de l'identifiant d'une publication.
const int maxPublicationIdLength = 128;

/// La longueur maximale de l'identifiant d'un dépôt.
const int maxDepositIdLength = 128;
