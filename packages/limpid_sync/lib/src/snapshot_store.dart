import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/transport/op_codec.dart';

/// The persisted state of a synchronised document.
///
/// ## The journal and the compacted state
///
/// A snapshot holds two things: the **compacted state** of the document — the
/// state the CRDT reaches — and the **journal** of the operations that are
/// not compacted yet.
///
/// The journal is the list of the operations the document has seen. It grows
/// with every edit, and the compaction replaces it with the state: the
/// operations the server accepted are replayed once, their effect is kept in
/// the state, and they leave the journal. The operations the server has not
/// accepted yet stay in the journal: they are the ones the client still owes
/// to the server.
///
/// The document is restored by applying the journal on top of the state,
/// which gives exactly the state the client held before the compaction.
final class DocumentSnapshot {
  /// Creates a snapshot.
  const DocumentSnapshot({
    required this.documentId,
    required this.since,
    required this.maxLamport,
    this.operations = const <SyncOp>[],
    this.state,
  });

  /// Creates the empty snapshot of [documentId].
  factory DocumentSnapshot.empty(DocumentId documentId) =>
      DocumentSnapshot(documentId: documentId, since: 0, maxLamport: 0);

  /// The document the snapshot belongs to.
  final DocumentId documentId;

  /// The cursor of the last operation pulled from the API.
  final int since;

  /// The highest Lamport timestamp observed for the document.
  final int maxLamport;

  /// The operations that are not compacted yet.
  ///
  /// The journal holds the operations the server has not accepted: they are
  /// applied on top of [state] when the document is restored.
  final List<SyncOp> operations;

  /// The compacted state of the document, `null` when the snapshot holds no
  /// compacted state.
  ///
  /// The state replaces the operations the server accepted. It is `null` for
  /// a document whose journal was never compacted.
  final CrdtState? state;

  /// Rebuilds the CRDT document from the state and the journal.
  CrdtDocument restore() {
    final CrdtDocument base =
        state?.toDocument() ?? CrdtDocument.empty(documentId);
    return base.applyAll(operations);
  }

  /// The keys of the operations the snapshot already holds.
  ///
  /// The set gathers the operations of the journal and the operations the
  /// compacted state already applied: an operation known here is never
  /// applied twice.
  Set<String> get knownOperationKeys => <String>{
    ...?state?.appliedKeys,
    ...operations.map((SyncOp operation) => operation.operationKey),
  };

  /// Returns a copy of this snapshot with the given fields replaced.
  DocumentSnapshot copyWith({
    DocumentId? documentId,
    int? since,
    int? maxLamport,
    List<SyncOp>? operations,
    CrdtState? state,
    bool clearState = false,
  }) {
    return DocumentSnapshot(
      documentId: documentId ?? this.documentId,
      since: since ?? this.since,
      maxLamport: maxLamport ?? this.maxLamport,
      operations: operations ?? this.operations,
      state: clearState ? null : (state ?? this.state),
    );
  }

  /// Encodes the snapshot as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'doc_id': documentId.value,
    'since': since,
    'max_lamport': maxLamport,
    'operations': operations.map(OpCodec.encode).toList(growable: false),
    if (state != null) 'state': state!.toJson(),
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
    final rawState = json['state'];
    final state = rawState is Map<String, Object?>
        ? CrdtState.fromJson(rawState, documentId: documentId)
        : null;
    return DocumentSnapshot(
      documentId: documentId,
      since: since is int ? since : 0,
      maxLamport: maxLamport is int ? maxLamport : 0,
      operations: operations,
      state: state,
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
