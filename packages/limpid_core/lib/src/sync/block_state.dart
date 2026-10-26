import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/enums.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/sync/ops.dart';
import 'package:limpid_core/src/sync/order_key.dart';

/// The information carried by the insertion of a block.
final class InsertInfo {
  /// Creates an insertion record.
  const InsertInfo({
    required this.lamport,
    required this.author,
    required this.parent,
    required this.order,
    required this.type,
    required this.content,
  });

  /// The Lamport timestamp of the insertion.
  final int lamport;

  /// The author of the insertion.
  final AuthorId author;

  /// The parent of the block.
  final BlockId? parent;

  /// The fractional index of the block.
  final OrderKey order;

  /// The kind of the block.
  final BlockType type;

  /// The initial content of the block.
  final BlockContent content;

  /// The identity of the insertion, used to order concurrent insertions.
  String get key => '$lamport/${author.value}';
}

/// One version of the content of a block.
///
/// Versions form a forest: each version points to the version it was derived
/// from, which is the common ancestor used by the 3-way text merge.
final class ContentVersion {
  /// Creates a content version.
  const ContentVersion({
    required this.lamport,
    required this.author,
    required this.content,
    this.base,
  });

  /// The Lamport timestamp of the operation that produced the version.
  final int lamport;

  /// The author of the operation that produced the version.
  final AuthorId author;

  /// The content of the version.
  final BlockContent content;

  /// The version this one derives from, `null` when written from scratch.
  final VersionRef? base;

  /// The identity of the version.
  VersionRef get ref => VersionRef(lamport: lamport, author: author);
}

/// The information carried by the latest move of a block.
final class MoveInfo {
  /// Creates a move record.
  const MoveInfo({
    required this.lamport,
    required this.author,
    required this.parent,
    required this.order,
  });

  /// The Lamport timestamp of the move.
  final int lamport;

  /// The author of the move.
  final AuthorId author;

  /// The new parent of the block.
  final BlockId? parent;

  /// The new fractional index of the block.
  final OrderKey order;

  /// The identity of the move, used to order concurrent moves.
  String get key => '$lamport/${author.value}';
}

/// The state of a mark inside a block.
final class MarkState {
  /// Creates a mark record.
  const MarkState({
    required this.addedAt,
    required this.addedBy,
    required this.type,
    required this.range,
    this.body = '',
  });

  /// The Lamport timestamp of the addition.
  final int addedAt;

  /// The author of the addition.
  final AuthorId addedBy;

  /// The nature of the mark.
  final MarkType type;

  /// The range covered by the mark.
  final MarkRange range;

  /// The body of the mark.
  final String body;
}

/// The value of a scalar metadata of the document.
final class MetaEntry {
  /// Creates a metadata record.
  const MetaEntry({
    required this.lamport,
    required this.author,
    required this.value,
  });

  /// The Lamport timestamp of the write.
  final int lamport;

  /// The author of the write.
  final AuthorId author;

  /// The value of the metadata.
  final String value;

  /// The identity of the write, used to order concurrent writes.
  String get key => '$lamport/${author.value}';
}

/// The accumulated state of a block, derived from the operations seen so far.
///
/// The state is immutable: applying an operation produces a new instance.
final class BlockState {
  /// Creates an empty block state.
  const BlockState({
    required this.id,
    this.insert,
    this.versions = const <ContentVersion>[],
    this.deletedAt,
    this.deletedBy,
    this.move,
    this.marks = const <MarkId, MarkState>{},
    this.removals = const <MarkId, int>{},
    this.opCount = 0,
  });

  /// The identifier of the block.
  final BlockId id;

  /// The insertion record, `null` while the insertion is unknown.
  final InsertInfo? insert;

  /// Every known content version of the block, ordered by creation.
  final List<ContentVersion> versions;

  /// The Lamport timestamp of the latest deletion.
  final int? deletedAt;

  /// The author of the latest deletion.
  final AuthorId? deletedBy;

  /// The latest move of the block.
  final MoveInfo? move;

  /// The marks attached to the block.
  final Map<MarkId, MarkState> marks;

  /// The Lamport timestamp of the removal of each removed mark.
  final Map<MarkId, int> removals;

  /// The number of operations applied to the block.
  final int opCount;

  /// The latest Lamport timestamp of a content modification.
  int get lastContentLamport {
    var latest = 0;
    for (final version in versions) {
      if (version.lamport > latest) latest = version.lamport;
    }
    return latest;
  }

  /// Whether the block is deleted: a deletion wins when it is strictly more
  /// recent than the latest content modification.
  bool get isDeleted {
    final deletion = deletedAt;
    if (deletion == null) return false;
    return deletion > lastContentLamport;
  }

  /// Returns a copy of this state with the given fields replaced.
  BlockState copyWith({
    InsertInfo? insert,
    List<ContentVersion>? versions,
    int? deletedAt,
    AuthorId? deletedBy,
    MoveInfo? move,
    Map<MarkId, MarkState>? marks,
    Map<MarkId, int>? removals,
    int? opCount,
  }) {
    return BlockState(
      id: id,
      insert: insert ?? this.insert,
      versions: versions ?? this.versions,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      move: move ?? this.move,
      marks: marks ?? this.marks,
      removals: removals ?? this.removals,
      opCount: opCount ?? this.opCount,
    );
  }

  /// Whether the mark [markId] is currently visible.
  bool isMarkPresent(MarkId markId) {
    final mark = marks[markId];
    if (mark == null) return false;
    final removal = removals[markId];
    if (removal == null) return true;
    return removal < mark.addedAt;
  }
}

/// Whether the `(lamport, author)` pair is strictly newer than the stored
/// version key.
///
/// The stored key is the `'<lamport>/<author>'` identity of an operation. The
/// comparison is the last-writer-wins rule of D-04: the Lamport timestamp
/// comes first and the author identifier breaks the ties.
bool isNewerVersion(int lamport, AuthorId author, String storedKey) {
  final separator = storedKey.indexOf('/');
  final storedLamport = int.parse(storedKey.substring(0, separator));
  final storedAuthor = storedKey.substring(separator + 1);
  if (lamport != storedLamport) return lamport > storedLamport;
  return author.value.compareTo(storedAuthor) > 0;
}
