import 'export_format.dart';
import 'ids.dart';

/// The lifecycle of an export job.
enum ExportJobStatus {
  /// Waiting in the job queue.
  queued,

  /// Currently being generated.
  running,

  /// Successfully generated.
  completed,

  /// Generation failed.
  failed,

  /// Cancelled by the author.
  cancelled,
}

/// An asynchronous export of a project (D-09).
final class ExportJob {
  /// Creates an export job.
  const ExportJob({
    required this.id,
    required this.projectId,
    required this.format,
    required this.requestedBy,
    required this.createdAt,
    this.status = ExportJobStatus.queued,
    this.progress = 0,
    this.downloadUrl,
    this.fileName,
    this.errorCode,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  /// Identifier of the job.
  final ExportJobId id;

  /// Project being exported.
  final ProjectId projectId;

  /// Format of the requested export.
  final ExportFormat format;

  /// Account that requested the export.
  final AuthorId requestedBy;

  /// Current status of the job.
  final ExportJobStatus status;

  /// Progress of the job, in `[0, 1]`.
  final double progress;

  /// Location of the generated file, `null` until completion.
  final String? downloadUrl;

  /// Name of the generated file.
  final String? fileName;

  /// Technical error code when the job failed.
  final String? errorCode;

  /// Human readable error message when the job failed.
  final String? errorMessage;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Timestamp of the start of the generation.
  final DateTime? startedAt;

  /// Timestamp of the end of the generation.
  final DateTime? completedAt;

  /// Whether the job reached a terminal state.
  bool get isFinished =>
      status == ExportJobStatus.completed ||
      status == ExportJobStatus.failed ||
      status == ExportJobStatus.cancelled;

  /// Whether the job succeeded.
  bool get isSuccessful => status == ExportJobStatus.completed;

  /// Returns a copy of this job with the given fields replaced.
  ExportJob copyWith({
    ExportJobStatus? status,
    double? progress,
    String? downloadUrl,
    String? fileName,
    String? errorCode,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return ExportJob(
      id: id,
      projectId: projectId,
      format: format,
      requestedBy: requestedBy,
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      fileName: fileName ?? this.fileName,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExportJob &&
          other.id == id &&
          other.projectId == projectId &&
          other.format == format &&
          other.requestedBy == requestedBy &&
          other.status == status &&
          other.progress == progress &&
          other.downloadUrl == downloadUrl &&
          other.fileName == fileName &&
          other.errorCode == errorCode &&
          other.errorMessage == errorMessage &&
          other.createdAt == createdAt &&
          other.startedAt == startedAt &&
          other.completedAt == completedAt);

  @override
  int get hashCode => Object.hash(
    ExportJob,
    id,
    projectId,
    format,
    requestedBy,
    status,
    progress,
    downloadUrl,
    fileName,
    errorCode,
    errorMessage,
    createdAt,
    startedAt,
    completedAt,
  );

  @override
  String toString() => 'ExportJob($id, $format, $status)';
}
