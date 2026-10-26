/// An operation of the sync journal, as stored by the API.
///
/// The record mirrors the `sync_ops` table: the identity of an operation is
/// the triple `(doc_id, lamport, author_id)`, which makes the push idempotent
/// (ARCHITECTURE.md §5.3).
final class SyncOpRecord {
  /// Creates an operation record.
  const SyncOpRecord({
    required this.opId,
    required this.projectId,
    required this.docId,
    required this.lamport,
    required this.authorId,
    required this.type,
    required this.payload,
    required this.schemaVersion,
    required this.createdAt,
  });

  /// The unique identifier of the operation, used for network deduplication.
  final String opId;

  /// The project the operation belongs to.
  final String projectId;

  /// The synchronised document, a scene in version 1.
  final String docId;

  /// The Lamport timestamp of the operation.
  final int lamport;

  /// The author of the operation.
  final String authorId;

  /// The kind of the operation, as defined by the sync protocol.
  final String type;

  /// The payload of the operation.
  final Map<String, dynamic> payload;

  /// The version of the sync protocol the operation was written with.
  final int schemaVersion;

  /// The creation timestamp.
  final DateTime createdAt;

  /// The stable identity of the operation, used to deduplicate pushes.
  String get operationKey => '$docId/$lamport/$authorId';

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'op_id': opId,
      'doc_id': docId,
      'lamport': lamport,
      'author_id': authorId,
      'type': type,
      'payload': payload,
      'schema_version': schemaVersion,
      'client_ts': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// The outcome of a batch of pushed operations.
final class AppendResult {
  /// Creates an append result.
  const AppendResult({
    required this.accepted,
    required this.duplicated,
    required this.maxLamport,
  });

  /// The operations stored by this push.
  final List<SyncOpRecord> accepted;

  /// The operations that were already stored.
  final List<SyncOpRecord> duplicated;

  /// The highest Lamport timestamp known for the project.
  final int maxLamport;
}
