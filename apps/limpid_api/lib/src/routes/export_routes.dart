import 'package:limpid_export/limpid_export.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../db/project_record.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/access_control.dart';
import '../services/book_builder.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';
import '../services/storage_usage.dart';
import '../services/webhook_dispatcher.dart';
import '../services/webhook_service.dart';
import '../storage/artifact_keys.dart';
import '../sync/tree_builder.dart';

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
/// [quota] porte le garde-fou des quotas : le quota d'exports est vérifié
/// avant la génération du fichier, le quota de stockage est vérifié avant
/// l'écriture de l'artefact, et le compteur n'est incrémenté qu'une fois,
/// après le succès de l'export. Le point de composition câble le service ;
/// sans lui, la route n'applique aucun plafond.
///
/// Le dispatcher est pris dans les dépendances : c'est lui qui porte la
/// livraison de la fin de l'export. La livraison part en arrière-plan, et
/// un rappel mort ne transforme jamais un export réussi en erreur.
///
/// Le corps de la requete choisit la couverture : `front` (le defaut) ou
/// `full`, la maquette complete. Le choix ne vaut que pour les PDF : les
/// autres formats portent toujours la couverture de face.
void registerExportRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  final WebhookDispatcher? dispatcher = dependencies.webhookDispatcher;
  router.post('/v1/export/<format>', (Request request, String format) async {
    final AuthContext auth = requireAuthContext(request);
    final ExportFormat exportFormat = _parseFormat(format);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String projectId = body.requireString('project_id');
    final CoverVariant coverVariant = _coverVariant(body);

    final ProjectAccess access = await AccessControl.requireProject(
      dependencies.projects,
      projectId,
      auth,
    );

    // Le garde-fou passe avant la génération : un compte qui a épuisé son
    // quota d'exports ne déclenche jamais la fabrication du livre.
    if (quota != null) {
      await quota.ensureCounter(
        userId: auth.userId,
        feature: QuotaFeature.exports,
      );
      if (exportFormat == ExportFormat.pdfPrintReady) {
        await quota.ensureCapability(
          userId: auth.userId,
          capability: PlanCapability.printReadyExports,
        );
      }
    }

    final List<SyncOpRecord> operations = await dependencies.sync.all(
      projectId: projectId,
    );
    final List<DocumentTree> trees = TreeBuilder.build(operations);

    final ExportBook book = await _buildBook(
      access.project,
      trees,
      dependencies.kdp,
    );
    final ExportResult result = await _export(
      exportFormat,
      book,
      _variantOf(exportFormat, coverVariant),
    );

    // Le garde-fou du stockage passe avant l'écriture : un compte dont le
    // stockage est plein refuse l'export, et l'artefact n'est jamais
    // écrit. Le livre est fabriqué en mémoire, il ne coûte donc rien au
    // compte — ni au fournisseur.
    if (quota != null) {
      final AccountStorageUsage storage = AccountStorageUsage(
        projects: dependencies.projects,
        storage: dependencies.storage,
      );
      await quota.ensureGaugeFits(
        userId: auth.userId,
        feature: QuotaFeature.storageBytes,
        current: await storage.bytesOf(auth.userId),
        charge: result.bytes.length,
      );
    }

    final String key =
        '${ArtifactKeys.prefixOfProject(projectId)}${result.fileName}';
    await dependencies.storage.put(
      key: key,
      bytes: result.bytes,
      contentType: result.mimeType,
    );

    // L'export a réussi : le compteur est incrémenté une fois, et une
    // seule.
    if (quota != null) {
      await quota.recordConsumption(
        userId: auth.userId,
        feature: QuotaFeature.exports,
      );
    }

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: 'export.requested',
        targetType: 'project',
        targetId: projectId,
        metadata: <String, Object?>{
          'format': exportFormat.name,
          'bytes': result.bytes.length,
        },
        ip: clientIpOf(request),
      ),
    );

    // L'export a réussi : l'intégration de l'auteur est prévenue. La
    // charge porte le projet, le format et la taille : ni le texte du
    // livre, ni le secret du point de rappel.
    dispatcher?.emit(
      userId: auth.userId,
      event: WebhookEvent.exportCompleted,
      data: <String, Object?>{
        'project_id': projectId,
        'format': exportFormat.name,
        'bytes': result.bytes.length,
      },
    );

    return Response.ok(
      result.bytes,
      headers: <String, String>{
        'content-type': result.mimeType,
        'content-length': '${result.bytes.length}',
        'content-disposition': 'attachment; filename="${result.fileName}"',
        'x-limpid-export-key': key,
      },
    );
  });
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

/// La variante de couverture d'un format.
///
/// La maquette complete ne vaut que pour le PDF : les autres formats
/// portent la couverture de face, une couverture etroite et le dos
/// n'y ont pas leur place.
CoverVariant _variantOf(ExportFormat format, CoverVariant variant) {
  final bool isPdf =
      format == ExportFormat.pdfReflowable ||
      format == ExportFormat.pdfPrintReady;
  return isPdf ? variant : CoverVariant.front;
}

/// Construit le livre exporte.
///
/// L'ISBN et l'auteur viennent de la fiche Amazon KDP du projet quand elle
/// existe : l'edition imprimee porte alors son code-barres. Un livre sans
/// fiche n'en porte pas : l'export n'invente jamais un ISBN.
Future<ExportBook> _buildBook(
  ProjectRecord project,
  List<DocumentTree> trees,
  KdpDatabase? kdp,
) async {
  final bool hasContent = trees.any(
    (DocumentTree tree) => tree.blocks.isNotEmpty,
  );
  if (!hasContent) {
    throw const ConflictException(
      message: "Ce projet n'a encore aucun contenu à exporter.",
    );
  }
  final KdpPublication? publication = await kdp?.findPublicationByProject(
    projectId: project.id,
  );
  return BookBuilder.build(
    project: project,
    trees: trees,
    isbn: publication?.isbn,
    author: publication?.author,
  );
}

Future<ExportResult> _export(
  ExportFormat format,
  ExportBook book,
  CoverVariant variant,
) async {
  try {
    // La couverture générée est attachée au livre avant l'export : les
    // formats qui l'embarquent (EPUB, ODT) la portent, ceux qui la nomment
    // (HTML, Markdown) la référencent.
    return await CoveredExporter(
      export: LimpidExporter().export,
      variant: variant,
    ).call(format, book, const ExportOptions());
  } on ExportException catch (error) {
    throw ExportFailedException(
      message: "L'export n'a pas pu être généré. Réessayez dans un instant.",
      details: <String, Object?>{'format': format.name},
      cause: error,
    );
  }
}

/// The JSON headers of a regular API response.
const Map<String, String> jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};
