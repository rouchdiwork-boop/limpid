import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/snapshot_store.dart';

/// The number of operations that triggers the compaction of a journal.
///
/// The value is the one documented in `docs/ARCHITECTURE.md` §5.4: a
/// document whose journal reaches five hundred operations is compacted.
const int compactionThreshold = 500;

/// The outcome of a compaction of a journal.
final class CompactionReport {
  /// Creates a report.
  const CompactionReport({
    required this.snapshot,
    required this.compactedOperations,
  });

  /// The snapshot the compaction produced.
  final DocumentSnapshot snapshot;

  /// The number of operations that left the journal.
  final int compactedOperations;

  /// Whether the compaction moved anything.
  bool get isCompacted => compactedOperations > 0;

  @override
  String toString() =>
      'CompactionReport($compactedOperations operations compacted)';
}

/// The compactor of the journal of a document.
///
/// ## What the compaction does
///
/// The journal of a document grows with every edit. When it reaches the
/// threshold, the operations the server accepted are replaced by the **state**
/// they produced: the journal is purged, and the document is restored from
/// the state instead of being replayed.
///
/// The compaction is **lossless**: the state it produces is exactly the state
/// the client reached by replaying the journal, block by block.
///
/// ## What it never does
///
/// The compaction never removes an operation the server has not accepted: the
/// client still owes it to the server, and the server may still refuse it.
/// The operations that wait for the server stay in the journal, in the order
/// they were applied, so the document is restored exactly as it was.
///
/// The compaction is **idempotent**: compacting a compacted snapshot gives
/// the same snapshot back.
final class JournalCompactor {
  /// Creates a compactor.
  const JournalCompactor({this.threshold = compactionThreshold});

  /// The number of operations that triggers the compaction.
  final int threshold;

  /// Compacts [snapshot] when its journal reaches the threshold.
  ///
  /// The keys of [unsyncedKeys] are the operations the server has not
  /// accepted yet: they are the ones the compaction must keep. The
  /// compaction is refused when the journal starts with one of them, because
  /// the operations that follow it would be replayed in another order.
  CompactionReport compact(
    DocumentSnapshot snapshot, {
    required Set<String> unsyncedKeys,
  }) {
    final List<SyncOp> journal = snapshot.operations;
    if (journal.length < threshold) {
      return CompactionReport(snapshot: snapshot, compactedOperations: 0);
    }
    final int compacted = _compactedPrefix(journal, unsyncedKeys);
    if (compacted == 0) {
      return CompactionReport(snapshot: snapshot, compactedOperations: 0);
    }
    final CrdtDocument base =
        snapshot.state?.toDocument() ?? CrdtDocument.empty(snapshot.documentId);
    final CrdtDocument document = base.applyAll(journal.sublist(0, compacted));
    return CompactionReport(
      snapshot: snapshot.copyWith(
        state: CrdtState.fromDocument(document),
        operations: List<SyncOp>.unmodifiable(journal.sublist(compacted)),
      ),
      compactedOperations: compacted,
    );
  }

  /// The number of operations at the head of the journal that may be
  /// compacted.
  ///
  /// The head of the journal stops at the first operation the server has not
  /// accepted: the operations that follow it would be replayed before it, and
  /// the order of the operations is part of the state.
  int _compactedPrefix(List<SyncOp> journal, Set<String> unsyncedKeys) {
    var compacted = 0;
    while (compacted < journal.length &&
        !unsyncedKeys.contains(journal[compacted].operationKey)) {
      compacted++;
    }
    return compacted;
  }
}
