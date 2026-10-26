import 'package:http/http.dart' as http;
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// The exports of a manuscript, produced by the API.
///
/// The generation happens on the server: `POST /v1/export/<format>` builds
/// the book, writes the artefact in the object storage and **answers the
/// file itself**. There is no job to follow and no signed URL to download:
/// the repository hands the bytes to the caller.
final class ApiExportRepository implements ExportRepository {
  /// Creates a repository on top of [client].
  ApiExportRepository({required this.client});

  /// The client of the API.
  final ApiClient client;

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    final http.Response response = await client.postRaw(
      '/v1/export/${_routeOf(format)}',
      body: <String, Object?>{'project_id': projectId},
    );
    return ExportArtefact(
      fileName:
          _fileNameOf(response.headers) ?? '$projectId.${format.fileExtension}',
      mimeType: response.headers['content-type'] ?? mimeTypeOf(format),
      bytes: response.bodyBytes,
    );
  }

  /// The name of the route of a format.
  ///
  /// The API names the formats the way the exporters name them, not the way
  /// the domain enum does: `epub`, `pdf`, `pdf-print`, `docx`, `html`, `md`
  /// and `odt`. The Kindle package is not produced by the API yet.
  static String _routeOf(ExportFormat format) => switch (format) {
    ExportFormat.epub3 => 'epub',
    ExportFormat.pdfReflowable => 'pdf',
    ExportFormat.pdfPrintReady => 'pdf-print',
    ExportFormat.docx => 'docx',
    ExportFormat.html => 'html',
    ExportFormat.markdown => 'md',
    ExportFormat.odt => 'odt',
    ExportFormat.kindleKpf => throw const ApiValidationException(
      'The Kindle package format is not produced by the API yet.',
      code: 'export_unsupported_format',
    ),
  };

  /// Reads the name of the file from the `content-disposition` header.
  static String? _fileNameOf(Map<String, String> headers) {
    final String? disposition = headers['content-disposition'];
    if (disposition == null) return null;
    final RegExpMatch? quoted = RegExp(
      r'filename="([^"]*)"',
    ).firstMatch(disposition);
    if (quoted != null) return quoted.group(1);
    final RegExpMatch? bare = RegExp(
      r'filename=([^;]+)',
    ).firstMatch(disposition);
    return bare?.group(1)?.trim();
  }
}
