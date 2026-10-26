import 'dart:io';

import 'package:limpid_export/limpid_export.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/export_job_record.dart';
import '../db/export_job_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/export_service.dart';
import '../services/quota_service.dart';

/// The formats accepted by the export route.
const Map<String, ExportFormat> exportFormats = <String, ExportFormat>{
  'epub': ExportFormat.epub3,
  'pdf': ExportFormat.pdfReflowable,
  'pdf-print': ExportFormat.pdfPrintReady,
  'docx': ExportFormat.docx,
  'html': ExportFormat.html,
  'md': ExportFormat.markdown,
  'odt': ExportFormat.odt,
};

/// Les variantes de couverture que la route accepte.
///
/// La couverture de face est le defaut ; la maquette complete porte le dos
/// et la tranche, c'est le gabarit imprime.
const Map<String, CoverVariant> exportCoverVariants = <String, CoverVariant>{
  'front': CoverVariant.front,
  'full': CoverVariant.full,
};

/// Registers the routes of the export.
///
/// L'export est un **travail** : la route ne fabrique pas le livre, elle
/// crée le travail et répond aussitot (`202` et l'identifiant du travail).
/// Un livre de 80 000 mots tiendrait la requête HTTP ouverte pendant des
/// dizaines de secondes : le proxy la coupe, et l'export serait perdu
/// après avoir facturé.
///
/// Quatre routes suivent la demande :
///
/// - `GET /v1/exports` liste les travaux du compte ;
/// - `GET /v1/exports/<jobId>` dit où en est le travail ;
/// - `GET /v1/exports/<jobId>/download` donne l'adresse signée de
///   l'artefact, jusqu'à son expiration ;
/// - `POST /v1/exports/<jobId>/retry` relance un travail **échoué** en
///   créant un travail **neuf** : un travail est un événement, il n'est
///   jamais rejoué.
///
/// [quota] porte le garde-fou des quotas : il est vérifié avant la
/// création du travail, et la consommation n'est comptée qu'au succès.
///
/// [jobs] est la file des travaux. Un serveur qui ne la câble pas ne sert
/// pas l'export : la route le dit clairement plutôt que de promettre un
/// fichier qu'elle ne produira pas.
///
/// [clock] rend l'heure injectable : les tests font passer le temps sans
/// attendre, et l'expiration de l'artefact se mesure ainsi.
void registerExportRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
  ExportJobStore? jobs,
  DateTime Function()? clock,
}) {
  final ExportService? service = jobs == null
      ? null
      : ExportService(
          jobs: jobs,
          projects: dependencies.projects,
          sync: dependencies.sync,
          storage: dependencies.storage,
          kdp: dependencies.kdp,
          quota: quota,
          audit: dependencies.audit,
          dispatcher: dependencies.webhookDispatcher,
          logger: dependencies.logger,
          clock: clock,
        );

  // La demande : le travail est créé, le livre n'est pas fabriqué ici.
  router.post('/v1/export/<format>', (Request request, String format) async {
    final ExportService export = _requireService(service);
    final AuthContext auth = requireAuthContext(request);
    final ExportFormat exportFormat = _parseFormat(format);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String projectId = body.requireString('project_id');
    final CoverVariant cover = _coverVariant(body);

    final ExportJobRecord job = await export.request(
      userId: auth.userId,
      projectId: projectId,
      format: exportFormat,
      cover: cover,
    );

    return ApiResponse.ok(
      await _payloadOf(export, job),
      status: HttpStatus.accepted,
    );
  });

  // La liste des travaux du compte : l'interface la relit après une
  // reconnexion, quand la notification a été perdue.
  router.get('/v1/exports', (Request request) async {
    final ExportService export = _requireService(service);
    final AuthContext auth = requireAuthContext(request);
    final List<ExportJobRecord> jobs = await export.jobs.listByUser(
      userId: auth.userId,
    );
    return ApiResponse.ok(<Map<String, Object?>>[
      for (final ExportJobRecord job in jobs) await _payloadOf(export, job),
    ]);
  });

  // La consultation : où en est le travail.
  router.get('/v1/exports/<jobId>', (Request request, String jobId) async {
    final ExportService export = _requireService(service);
    final AuthContext auth = requireAuthContext(request);
    final ExportJobRecord job = await _requireJob(export, auth, jobId);
    return ApiResponse.ok(await _payloadOf(export, job));
  });

  // La relance : un travail échoué devient un travail **neuf**.
  router.post('/v1/exports/<jobId>/retry', (
    Request request,
    String jobId,
  ) async {
    final ExportService export = _requireService(service);
    final AuthContext auth = requireAuthContext(request);
    final ExportJobRecord failed = await _requireJob(export, auth, jobId);
    if (failed.status != ExportJobStatus.failed) {
      throw const ConflictException(
        message: 'Seul un travail en échec peut être relancé.',
      );
    }
    final ExportJobRecord job = await export.retry(failed);
    return ApiResponse.ok(
      await _payloadOf(export, job),
      status: HttpStatus.accepted,
    );
  });

  // Le téléchargement : l'adresse signée de l'artefact, jusqu'à son
  // expiration.
  router.get('/v1/exports/<jobId>/download', (
    Request request,
    String jobId,
  ) async {
    final ExportService export = _requireService(service);
    final AuthContext auth = requireAuthContext(request);
    final ExportJobRecord job = await _requireJob(export, auth, jobId);
    final String? key = job.artifactKey;
    if (job.status != ExportJobStatus.succeeded || key == null) {
      throw const NotFoundException(
        message: "Ce fichier n'est pas disponible.",
      );
    }
    final DateTime now = export.now;
    if (job.isExpiredAt(now)) {
      throw const NotFoundException(
        message: "Ce fichier a expiré : il n'est plus téléchargeable.",
      );
    }
    final String url = await dependencies.storage.presignedUrl(
      key: key,
      expires: job.expiresAt!.difference(now),
    );
    return ApiResponse.ok(<String, Object?>{
      'download_url': url,
      'file_name': _fileNameOf(key),
      'expires_at': job.expiresAt!.toUtc().toIso8601String(),
    });
  });
}

/// Le service d'export, ou l'erreur qui dit que la file n'est pas câblée.
ExportService _requireService(ExportService? service) {
  if (service == null) {
    throw const ServiceUnavailableException(
      message:
          "La file d'export n'est pas configurée sur ce poste : l'export "
          'est indisponible.',
    );
  }
  return service;
}

/// Le travail [jobId], quand il appartient à l'appelant.
///
/// Un travail d'un autre compte est rapporté comme absent : son existence
/// n'est pas divulguée.
Future<ExportJobRecord> _requireJob(
  ExportService export,
  AuthContext auth,
  String jobId,
) async {
  final ExportJobRecord? job = await export.read(jobId);
  if (job == null || job.userId != auth.userId) {
    throw const NotFoundException();
  }
  return job;
}

/// La charge du travail.
///
/// La charge porte l'adresse de téléchargement quand l'artefact est prêt
/// et vivant : l'adresse est signée, et elle porte sa propre expiration.
/// Un travail terminé dont l'artefact a expiré ne porte plus d'adresse : il
/// est prêt, mais il n'est plus téléchargeable.
Future<Map<String, Object?>> _payloadOf(
  ExportService export,
  ExportJobRecord job,
) async {
  String? downloadUrl;
  String? fileName;
  final String? key = job.artifactKey;
  if (job.status == ExportJobStatus.succeeded &&
      key != null &&
      !job.isExpiredAt(export.now)) {
    downloadUrl = await export.storage.presignedUrl(
      key: key,
      expires: job.expiresAt!.difference(export.now),
    );
    fileName = _fileNameOf(key);
  }
  return <String, Object?>{
    ...job.toJson(),
    'download_url': downloadUrl,
    'file_name': fileName,
  };
}

/// Le nom du fichier produit, tel qu'il est rangé dans le stockage.
String _fileNameOf(String key) {
  final int slash = key.lastIndexOf('/');
  if (slash < 0 || slash == key.length - 1) return key;
  return key.substring(slash + 1);
}

ExportFormat _parseFormat(String format) {
  final ExportFormat? parsed = exportFormats[format.toLowerCase()];
  if (parsed == null) {
    throw ValidationException(
      field: 'format',
      message:
          'Le format « $format » est inconnu. Formats acceptés : '
          '${exportFormats.keys.join(', ')}.',
    );
  }
  return parsed;
}

/// La variante de couverture demandee par le corps de la requete.
///
/// La couverture de face est le defaut ; la maquette complete se demande
/// explicitement. Le nom invalide est refuse : il nomme ce qu'il faut
/// corriger.
CoverVariant _coverVariant(JsonBody body) {
  final String? raw = body.optionalString('cover', maxLength: 16);
  if (raw == null || raw.trim().isEmpty) {
    return CoverVariant.front;
  }
  final CoverVariant? variant = CoverVariant.tryParse(raw);
  if (variant == null || !exportCoverVariants.containsKey(variant.name)) {
    throw ValidationException(
      field: 'cover',
      message:
          'Le champ « cover » doit valoir « front » (la couverture de '
          'face) ou « full » (la maquette complète, dos et tranche).',
    );
  }
  return variant;
}

/// The JSON headers of a regular API response.
const Map<String, String> jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};
