import 'sync_op_record.dart';

/// The persistence port of the sync journal.
///
/// The journal is append-only and idempotent by `(doc_id, lamport,
/// author_id)`, which is the structural idempotence of ARCHITECTURE.md §5.3.
abstract interface class SyncStore {
  /// Appends [operations] to the journal of [projectId].
  ///
  /// The operations already stored are reported as duplicates, never stored
  /// twice.
  Future<AppendResult> append({
    required String projectId,
    required List<SyncOpRecord> operations,
  });

  /// Reads the operations of [projectId] with a Lamport timestamp strictly
  /// greater than [lamport].
  Future<List<SyncOpRecord>> since({
    required String projectId,
    required int lamport,
    required int limit,
  });

  /// Reads every operation of [projectId], ordered by Lamport timestamp.
  Future<List<SyncOpRecord>> all({required String projectId});

  /// The identifiers of the projects holding at least one operation of [docId].
  ///
  /// The journal is the only place where the documents are recorded, so it is
  /// the authority of the binding between a document and its project: an empty
  /// set means the server never saw the document, and it belongs to no project
  /// yet.
  Future<Set<String>> projectsOfDocument(String docId);
}
