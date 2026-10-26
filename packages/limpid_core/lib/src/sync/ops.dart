import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/enums.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/sync/order_key.dart';

/// A reference to a specific version of the content of a block.
///
/// A version is identified by the Lamport timestamp and the author of the
/// operation that produced it, which is exactly the identity of a sync
/// operation.
final class VersionRef {
  /// Creates a version reference.
  const VersionRef({required this.lamport, required this.author});

  /// The Lamport timestamp of the operation that produced the version.
  final int lamport;

  /// The author of the operation that produced the version.
  final AuthorId author;

  /// The stable textual identity of the version.
  String get key => '$lamport/${author.value}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VersionRef &&
          other.lamport == lamport &&
          other.author == author);

  @override
  int get hashCode => Object.hash(VersionRef, lamport, author);

  @override
  String toString() => 'VersionRef($key)';
}

/// A reference to the content version an update was derived from.
///
/// It is the common ancestor used by the 3-way text merge.
final class ContentBase {
  /// Creates a content base reference.
  const ContentBase({required this.version});

  /// The version this content derives from.
  final VersionRef version;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentBase &&
          other.version.lamport == version.lamport &&
          other.version.author == version.author);

  @override
  int get hashCode => Object.hash(ContentBase, version.lamport, version.author);

  @override
  String toString() => 'ContentBase(${version.key})';
}

/// An append-only operation of the CRDT.
///
/// Operations are idempotent: the identity of an operation is the triple
/// `(doc, lamport, author)`, and applying the same operation twice never
/// changes the state twice.
sealed class SyncOp {
  /// Creates a sync operation.
  const SyncOp({
    required this.doc,
    required this.lamport,
    required this.author,
  });

  /// The document the operation applies to.
  final DocumentId doc;

  /// The Lamport timestamp of the operation.
  final int lamport;

  /// The author of the operation.
  final AuthorId author;

  /// The stable textual identity of the operation.
  String get operationKey => '${doc.value}/$lamport/${author.value}';

  /// The kind of the operation, used for logging and metrics.
  String get kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOp && other.runtimeType == runtimeType && _same(other));

  @override
  int get hashCode => Object.hash(runtimeType, doc, lamport, author);

  /// Whether [other] carries the same payload as this operation.
  bool _same(SyncOp other);
}

/// Inserts a new block in the document tree.
final class InsertBlockOp extends SyncOp {
  /// Creates an insert operation.
  const InsertBlockOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.blockId,
    required this.parent,
    required this.order,
    required this.type,
    required this.content,
  });

  /// The block to create.
  final BlockId blockId;

  /// The parent of the block, `null` for a root block.
  final BlockId? parent;

  /// The fractional index of the block among its siblings.
  final OrderKey order;

  /// The kind of the block.
  final BlockType type;

  /// The initial content of the block.
  final BlockContent content;

  @override
  String get kind => 'insertBlock';

  @override
  bool _same(SyncOp other) {
    final op = other as InsertBlockOp;
    return op.blockId == blockId &&
        op.parent == parent &&
        op.order == order &&
        op.type == type &&
        op.content == content;
  }

  @override
  String toString() => 'InsertBlockOp($blockId, $lamport)';
}

/// Marks a block as deleted (reversible tombstone).
final class DeleteBlockOp extends SyncOp {
  /// Creates a delete operation.
  const DeleteBlockOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.blockId,
  });

  /// The block to delete.
  final BlockId blockId;

  @override
  String get kind => 'deleteBlock';

  @override
  bool _same(SyncOp other) {
    final op = other as DeleteBlockOp;
    return op.blockId == blockId;
  }

  @override
  String toString() => 'DeleteBlockOp($blockId, $lamport)';
}

/// Replaces the content of a block.
final class UpdateContentOp extends SyncOp {
  /// Creates an update operation.
  const UpdateContentOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.blockId,
    required this.content,
    this.base,
  });

  /// The block whose content is replaced.
  final BlockId blockId;

  /// The new content of the block.
  final BlockContent content;

  /// The content version this update derives from, `null` when the author
  /// wrote the block from scratch.
  final ContentBase? base;

  @override
  String get kind => 'updateContent';

  @override
  bool _same(SyncOp other) {
    final op = other as UpdateContentOp;
    return op.blockId == blockId && op.content == content && op.base == base;
  }

  @override
  String toString() => 'UpdateContentOp($blockId, $lamport)';
}

/// Moves a block to another position in the tree.
final class MoveBlockOp extends SyncOp {
  /// Creates a move operation.
  const MoveBlockOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.blockId,
    required this.parent,
    required this.order,
  });

  /// The block to move.
  final BlockId blockId;

  /// The new parent of the block.
  final BlockId? parent;

  /// The new fractional index of the block.
  final OrderKey order;

  @override
  String get kind => 'moveBlock';

  @override
  bool _same(SyncOp other) {
    final op = other as MoveBlockOp;
    return op.blockId == blockId && op.parent == parent && op.order == order;
  }

  @override
  String toString() => 'MoveBlockOp($blockId, $lamport)';
}

/// Sets a scalar metadata of the document (title, status…).
final class SetMetaOp extends SyncOp {
  /// Creates a metadata operation.
  const SetMetaOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.key,
    required this.value,
  });

  /// The metadata key.
  final String key;

  /// The metadata value.
  final String value;

  @override
  String get kind => 'setMeta';

  @override
  bool _same(SyncOp other) {
    final op = other as SetMetaOp;
    return op.key == key && op.value == value;
  }

  @override
  String toString() => 'SetMetaOp($key, $lamport)';
}

/// Adds a mark (comment, AI note) on a range of a block.
final class AddMarkOp extends SyncOp {
  /// Creates an add-mark operation.
  const AddMarkOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.markId,
    required this.blockId,
    required this.type,
    required this.range,
    this.body = '',
  });

  /// The mark to add.
  final MarkId markId;

  /// The block the mark is anchored to.
  final BlockId blockId;

  /// The nature of the mark.
  final MarkType type;

  /// The range covered by the mark.
  final MarkRange range;

  /// The body of the mark.
  final String body;

  @override
  String get kind => 'addMark';

  @override
  bool _same(SyncOp other) {
    final op = other as AddMarkOp;
    return op.markId == markId &&
        op.blockId == blockId &&
        op.type == type &&
        op.range == range &&
        op.body == body;
  }

  @override
  String toString() => 'AddMarkOp($markId, $lamport)';
}

/// Removes a mark from a block.
final class RemoveMarkOp extends SyncOp {
  /// Creates a remove-mark operation.
  const RemoveMarkOp({
    required super.doc,
    required super.lamport,
    required super.author,
    required this.markId,
    required this.blockId,
  });

  /// The mark to remove.
  final MarkId markId;

  /// The block the mark belongs to.
  final BlockId blockId;

  @override
  String get kind => 'removeMark';

  @override
  bool _same(SyncOp other) {
    final op = other as RemoveMarkOp;
    return op.markId == markId && op.blockId == blockId;
  }

  @override
  String toString() => 'RemoveMarkOp($markId, $lamport)';
}
