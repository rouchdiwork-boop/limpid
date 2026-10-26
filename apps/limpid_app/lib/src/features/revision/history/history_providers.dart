import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// The revisions of a document, the oldest first.
///
/// The provider reads the CRDT document of the scene: the forest of the
/// versions of the blocks is the history of the manuscript.
final historyRevisionsProvider =
    FutureProvider.family<List<DocumentRevision>, String>((
      Ref ref,
      String documentId,
    ) async {
      return ref.watch(revisionRepositoryProvider).loadRevisions(documentId);
    });

/// The comparison of two revisions of a document, block by block.
final historyComparisonProvider =
    FutureProvider.family<RevisionComparison, HistorySelection>((
      Ref ref,
      HistorySelection selection,
    ) async {
      return ref
          .watch(revisionRepositoryProvider)
          .compareRevisions(
            selection.documentId,
            from: selection.from,
            to: selection.to,
          );
    });

/// The two revisions the screen compares.
@immutable
class HistorySelection {
  /// Creates a selection.
  const HistorySelection({
    required this.documentId,
    required this.from,
    required this.to,
  });

  /// The document the revisions belong to.
  final String documentId;

  /// The revision the comparison starts from.
  final VersionRef from;

  /// The revision the comparison ends at.
  final VersionRef to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistorySelection &&
          other.documentId == documentId &&
          other.from == from &&
          other.to == to);

  @override
  int get hashCode => Object.hash(documentId, from, to);

  @override
  String toString() => 'HistorySelection($documentId, $from -> $to)';
}
