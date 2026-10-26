import 'package:http/http.dart' as http;
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/export_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// The exports of a manuscript, produced by the API.
///
/// The generation happens on the server: `POST /v1/export/<format>` creates
/// a **job**, the server prepares the book in the background, and the
/// application comes back for the file with `GET /v1/exports/<id>`.
///
/// The job is an event: it is never replayed. A retry creates a new job.
final class ApiExportRepository
    implements ExportRepository, ExportJobRepository {
  /// Creates a repository on top of [client].
  ApiExportRepository({required this.client});

  /// The client of the API.
  final ApiClient client;

  /// The delay between two readings of the state of a job.
  static const Duration pollInterval = Duration(seconds: 1);

  /// The number of readings before the wait gives up.
  ///
  /// Two minutes suffisent a the fabrication la plus lente — le PDF
  /// print-ready d'un livre de 80 000 mots.
  static const int pollLimit = 120;

  @override
  Future<ExportProgress> start({
    required String projectId,
    required ExportFormat format,
  }) async {
    final Object? payload = await client.post(
      '/v1/export/${_routeOf(format)}',
      body: <String, Object?>{'project_id': projectId},
    );
    return _progressOf(payload);
  }

  @override
  Future<ExportProgress> read(String jobId) async {
    final Object? payload = await client.get('/v1/exports/$jobId');
    return _progressOf(payload);
  }

  @override
  Future<ExportProgress> retry(String jobId) async {
    final Object? payload = await client.post('/v1/exports/$jobId/retry');
    return _progressOf(payload);
  }

  @override
  Future<ExportArtefact> download(ExportReady ready) async {
    final http.Response response = await client.download(ready.downloadUrl);
    return ExportArtefact(
      fileName: ready.fileName ?? 'export',
      mimeType: response.headers['content-type'] ?? 'application/octet-stream',
      bytes: response.bodyBytes,
    );
  }

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    final ExportProgress started = await start(
      projectId: projectId,
      format: format,
    );
    final ExportProgress finished = await _waitFor(started.id);
    if (finished is! ExportReady) {
      throw const ApiValidationException(
        'The export did not produce a file.',
        code: 'export_failed',
      );
    }
    return download(finished);
  }

  /// Attend la fin du travail [jobId].
  ///
  /// La lecture s'arrete des que le travail aboutit ou echoue : le fichier
  /// est pret, ou le message d'echec est la.
  Future<ExportProgress> _waitFor(String jobId) async {
    for (int attempt = 0; attempt < pollLimit; attempt++) {
      final ExportProgress progress = await read(jobId);
      if (progress is ExportReady || progress is ExportFailed) {
        return progress;
      }
      await Future<void>.delayed(pollInterval);
    }
    throw const ApiTimeoutException(
      'The export did not finish before the timeout.',
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

  /// The state of a job, read from the answer of the API.
  ///
  /// An answer the application does not understand is an error : l'ecran
  /// ne montre jamais un travail dans un etat qu'il ne sait pas dire.
  static ExportProgress _progressOf(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the job of the export.',
      );
    }
    final Object? id = payload['id'];
    final Object? status = payload['status'];
    if (id is! String || status is! String) {
      throw const ApiMalformedResponseException(
        'The API did not return the job of the export.',
      );
    }
    return switch (status) {
      'queued' => ExportQueued(id),
      'running' => ExportRunning(id),
      'succeeded' => ExportReady(
        id: id,
        downloadUrl: _addressOf(payload),
        expiresAt: _dateOf(payload['expires_at']),
        fileName: payload['file_name'] as String?,
      ),
      'failed' => ExportFailed(
        id: id,
        message: payload['error'] as String? ?? 'The export failed.',
      ),
      _ => throw const ApiMalformedResponseException(
        'The API returned an unknown state of the export.',
      ),
    };
  }

  /// The signed address of the produced file.
  static Uri _addressOf(Map<String, Object?> payload) {
    final Object? address = payload['download_url'];
    if (address is! String || address.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the download address.',
      );
    }
    return Uri.parse(address);
  }

  /// An instant read from the answer of the API.
  static DateTime? _dateOf(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
