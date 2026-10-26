import 'package:limpid_export/limpid_export.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/project_record.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/access_control.dart';
import '../services/book_builder.dart';
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

/// Registers the routes of the export.
void registerExportRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  router.post('/v1/export/<format>', (Request request, String format) async {
    final AuthContext auth = requireAuthContext(request);
    final ExportFormat exportFormat = _parseFormat(format);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String projectId = body.requireString('project_id');

    final ProjectAccess access = await AccessControl.requireProject(
      dependencies.projects,
      projectId,
      auth,
    );
    final List<SyncOpRecord> operations = await dependencies.sync.all(
      projectId: projectId,
    );
    final List<DocumentTree> trees = TreeBuilder.build(operations);

    final ExportBook book = _buildBook(access.project, trees);
    final ExportResult result = await _export(exportFormat, book);

    final String key = 'exports/$projectId/${result.fileName}';
    await dependencies.storage.put(
      key: key,
      bytes: result.bytes,
      contentType: result.mimeType,
    );

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

ExportBook _buildBook(ProjectRecord project, List<DocumentTree> trees) {
  final bool hasContent = trees.any(
    (DocumentTree tree) => tree.blocks.isNotEmpty,
  );
  if (!hasContent) {
    throw const ConflictException(
      message: "Ce projet n'a encore aucun contenu à exporter.",
    );
  }
  return BookBuilder.build(project: project, trees: trees);
}

Future<ExportResult> _export(ExportFormat format, ExportBook book) async {
  try {
    // La couverture générée est attachée au livre avant l'export : les
    // formats qui l'embarquent (EPUB, ODT) la portent, ceux qui la nomment
    // (HTML, Markdown) la référencent.
    return await CoveredExporter(
      export: LimpidExporter().export,
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
