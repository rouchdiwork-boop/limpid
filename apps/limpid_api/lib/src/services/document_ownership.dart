import '../db/sync_store.dart';
import '../errors/app_exception.dart';

/// The binding between a document and the project that owns it.
///
/// ## The rule
///
/// A `doc_id` belongs to the project the server has seen an operation for.
/// The journal of the synchronisation (`sync_ops`) is the only place where the
/// documents are recorded, so it is the authority of the binding: a document
/// the server never saw belongs to no project yet, and the first project
/// that writes an operation for it takes it.
///
/// A document is therefore reachable only through the project that owns it.
/// The relay refuses to open a room on a document the project does not hold,
/// and refuses to write an operation for a document owned by another project:
/// a document id can never carry traffic from one project to another.
///
/// ## The consequence for a new document
///
/// A document that does not exist yet cannot be joined: the relay only opens
/// a room on a document the journal already knows. A new document is born
/// from a push on the route of the project
/// (`POST /v1/projects/<projectId>/ops`), which binds it to that project;
/// the relay then relays its operations.
abstract final class DocumentOwnership {
  /// Whether [projectId] holds [docId].
  ///
  /// The answer is `false` for a document the server never saw: such a
  /// document belongs to no project yet.
  static Future<bool> owns(
    SyncStore store, {
    required String projectId,
    required String docId,
  }) async {
    final Set<String> owners = await store.projectsOfDocument(docId);
    return owners.contains(projectId);
  }

  /// Whether an operation may be written for [docId] in [projectId].
  ///
  /// A document owned by another project is refused: the write would give
  /// the same document id to two projects, and the relay could no longer tell
  /// which project a room belongs to.
  static Future<bool> mayWrite(
    SyncStore store, {
    required String projectId,
    required String docId,
  }) async {
    final Set<String> owners = await store.projectsOfDocument(docId);
    return owners.isEmpty || owners.contains(projectId);
  }

  /// The error answering a refused access to a document.
  ///
  /// The error is a not-found: the answer never confirms that the document
  /// exists in another project.
  static NotFoundException notFound() {
    return const NotFoundException(
      message: "Ce document n'existe pas dans ce projet.",
    );
  }
}
