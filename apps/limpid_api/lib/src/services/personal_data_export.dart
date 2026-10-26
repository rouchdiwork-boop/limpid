import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../sync/tree_builder.dart';

/// The number of audit entries carried by the export.
///
/// The journal is read back with a bound: the export answers the personal
/// data of an author, not the whole history of the service.
const int personalDataAuditLimit = 1000;

/// The version of the format of the export.
///
/// The format grows with the product: the version tells the author which
/// shape they received.
const int personalDataExportFormatVersion = 1;

/// The service building the export of the personal data of an author.
///
/// The export crosses the persistence ports: the projects, the operations of
/// the synchronisation journal, the documents they rebuild and the audit
/// entries of the author. Nothing is reconstructed out of thin air — every
/// value comes from the store it belongs to.
final class PersonalDataExportService {
  /// Creates the service.
  const PersonalDataExportService({
    required this.projects,
    required this.sync,
    required this.audit,
  });

  /// The store of the projects.
  final ProjectStore projects;

  /// The store of the synchronisation journal.
  final SyncStore sync;

  /// The audit journal.
  final AuditLog audit;

  /// Builds the export of the personal data of [userId].
  ///
  /// The payload never carries the session of another author: the projects
  /// are the ones the author owns or collaborates on, and the audit entries
  /// are the ones that concern them.
  ///
  /// Nor does it carry the **work** of another author. On a project the
  /// author only collaborates on, the export keeps their own operations and
  /// nothing else: the manuscript of a co-author is not the personal data of
  /// the author who asks for the export. On a project the author **owns**,
  /// the whole manuscript is theirs — it is their book — and it is exported
  /// whole.
  Future<Map<String, Object?>> build({
    required String userId,
    required String email,
    DateTime? exportedAt,
  }) async {
    final DateTime moment = exportedAt ?? DateTime.now().toUtc();
    final List<ProjectRecord> owned = await projects.listAll(userId: userId);

    final List<Map<String, Object?>> projectPayloads = <Map<String, Object?>>[];
    var documentCount = 0;
    var operationCount = 0;

    for (final ProjectRecord project in owned) {
      final List<SyncOpRecord> allOperations = await sync.all(
        projectId: project.id,
      );
      final bool isOwner = project.ownerId == userId;
      final List<SyncOpRecord> operations = isOwner
          ? allOperations
          : allOperations
                .where((SyncOpRecord operation) => operation.authorId == userId)
                .toList(growable: false);
      final List<DocumentTree> documents = TreeBuilder.build(operations);
      documentCount += documents.length;
      operationCount += operations.length;
      projectPayloads.add(
        _projectPayload(
          project: project,
          documents: documents,
          operations: operations,
          isOwner: isOwner,
        ),
      );
    }

    final List<AuditEntry> entries = await audit.entriesOf(
      userId: userId,
      limit: personalDataAuditLimit,
    );

    return <String, Object?>{
      'account': <String, Object?>{
        'user_id': userId,
        'email': email,
        'exported_at': moment.toUtc().toIso8601String(),
        'format_version': personalDataExportFormatVersion,
      },
      'projects': projectPayloads,
      'audit_log': entries
          .map((AuditEntry entry) => entry.toJson())
          .toList(growable: false),
      'counts': <String, Object?>{
        'projects': projectPayloads.length,
        'documents': documentCount,
        'sync_operations': operationCount,
        'audit_entries': entries.length,
      },
    };
  }

  /// Builds the payload of one project.
  ///
  /// The manuscript is stored as a journal of operations: a document is a
  /// scene, and the export book maps one document to one chapter
  /// (see `BookBuilder`). The export keeps that mapping, so the author
  /// reads the same structure as the one they wrote.
  Map<String, Object?> _projectPayload({
    required ProjectRecord project,
    required List<DocumentTree> documents,
    required List<SyncOpRecord> operations,
    required bool isOwner,
  }) {
    return <String, Object?>{
      'project': _projectJson(project),
      'chapters': _chapters(documents),
      'documents': documents
          .map((DocumentTree document) => document.toJson())
          .toList(growable: false),
      'sync_operations': operations
          .map((SyncOpRecord operation) => operation.toJson())
          .toList(growable: false),
      // The export says what it does not carry: on a project the author
      // only collaborates on, the operations and the manuscript of the
      // co-authors are absent.
      'scope': isOwner ? 'owner' : 'contribution',
    };
  }

  /// The full row of the project, the soft deletion included.
  ///
  /// The export carries the deleted projects too: their rows live for thirty
  /// days (D-19) and belong to the author until the purge.
  Map<String, Object?> _projectJson(ProjectRecord project) {
    return <String, Object?>{
      'id': project.id,
      'owner_id': project.ownerId,
      'title': project.title,
      'synopsis': project.synopsis,
      'status': project.status.name,
      'language': project.language,
      'order_key': project.orderKey,
      'is_public': project.isPublic,
      'created_at': project.createdAt.toUtc().toIso8601String(),
      'updated_at': project.updatedAt.toUtc().toIso8601String(),
      'deleted_at': project.deletedAt?.toUtc().toIso8601String(),
    };
  }

  /// The chapters of a project, one per document.
  List<Map<String, Object?>> _chapters(List<DocumentTree> documents) {
    final List<Map<String, Object?>> chapters = <Map<String, Object?>>[];
    for (var index = 0; index < documents.length; index++) {
      final DocumentTree document = documents[index];
      final String title = document.meta['title'] ?? 'Chapitre ${index + 1}';
      chapters.add(<String, Object?>{
        'id': document.docId,
        'title': title,
        'order': index,
        'scenes': <Map<String, Object?>>[
          <String, Object?>{
            'id': document.docId,
            'document_id': document.docId,
            'title': title,
          },
        ],
      });
    }
    return chapters;
  }
}
