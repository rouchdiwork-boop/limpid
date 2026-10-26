import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/transport/op_codec.dart';

/// The persisted state of a synchronised document.
///
/// ## Why the operations are stored instead of the blocks
///
/// `limpid_core` does not expose a serializer for [CrdtDocument]: the
/// document keeps the version forest of every block, the tombstones and the
/// set of the applied operations, and that state cannot be rebuilt from the
/// public blocks alone (the merge base of the 3-way text merge would be
/// lost).
///
/// The snapshot therefore stores the **compacted operation journal**: the
/// document is restored by replaying it, which is deterministic and gives
/// exactly the same state as the original replica. The compaction of
/// `docs/ARCHITECTURE.md` §5.4 can prune the journal later without changing
/// the semantics.
final class DocumentSnapshot {
  /// Creates a snapshot.
  const DocumentSnapshot({
    required this.documentId,
    required this.since,
    required this.maxLamport,
    required this.operations,
  });

  /// Creates the empty snapshot of [documentId].
  factory DocumentSnapshot.empty(DocumentId documentId) => DocumentSnapshot(
    documentId: documentId,
    since: 0,
    maxLamport: 0,
    operations: const <SyncOp>[],
  );

  /// The document the snapshot belongs to.
  final DocumentId documentId;

  /// The cursor of the last operation pulled from the API.
  final int since;

  /// The highest Lamport timestamp observed for the document.
  final int maxLamport;

  /// The operations that produced the state of the document.
  final List<SyncOp> operations;

  /// Rebuilds the CRDT document from the journal.
  CrdtDocument restore() => CrdtDocument.empty(documentId).applyAll(operations);

  /// Encodes the snapshot as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'doc_id': documentId.value,
    'since': since,
    'max_lamport': maxLamport,
    'operations': operations.map(OpCodec.encode).toList(growable: false),
  };

  /// Decodes a snapshot from its JSON representation.
  static DocumentSnapshot fromJson(Map<String, Object?> json) {
    final documentId = DocumentId(json['doc_id'] as String? ?? '');
    final since = json['since'];
    final maxLamport = json['max_lamport'];
    final rawOperations = json['operations'];
    final operations = rawOperations is List<Object?>
        ? OpCodec.decodeList(rawOperations)
        : const <SyncOp>[];
    return DocumentSnapshot(
      documentId: documentId,
      since: since is int ? since : 0,
      maxLamport: maxLamport is int ? maxLamport : 0,
      operations: operations,
    );
  }
}

/// The persistence seam of the local document snapshots.
abstract interface class SnapshotStore {
  /// Returns the snapshot of [documentId], `null` when it is unknown.
  Future<DocumentSnapshot?> read(DocumentId documentId);

  /// Writes [snapshot], replacing the previous one of the same document.
  Future<void> write(DocumentSnapshot snapshot);

  /// Removes the snapshot of [documentId].
  Future<void> remove(DocumentId documentId);
}

/// A [SnapshotStore] keeping the snapshots in memory.
final class InMemorySnapshotStore implements SnapshotStore {
  /// Creates an empty store.
  InMemorySnapshotStore();

  final Map<String, DocumentSnapshot> _snapshots = <String, DocumentSnapshot>{};

  @override
  Future<DocumentSnapshot?> read(DocumentId documentId) async {
    return _snapshots[documentId.value];
  }

  @override
  Future<void> write(DocumentSnapshot snapshot) async {
    _snapshots[snapshot.documentId.value] = snapshot;
  }

  @override
  Future<void> remove(DocumentId documentId) async {
    _snapshots.remove(documentId.value);
  }
}
