import 'package:limpid_core/src/sync/order_key.dart';

import 'content.dart';
import 'enums.dart';
import 'ids.dart';
import 'mark.dart';

/// An immutable block of the manuscript tree.
///
/// A block is the atomic unit of the CRDT: it owns its position ([order]),
/// its content, its marks and its tombstone flag. Blocks are never mutated;
/// the CRDT engine produces new instances through [copyWith].
final class Block {
  /// Creates a block.
  const Block({
    required this.id,
    required this.doc,
    required this.parent,
    required this.order,
    required this.type,
    required this.content,
    required this.lamport,
    required this.author,
    required this.version,
    this.marks = const <MarkId, MarkRange>{},
    this.deleted = false,
  });

  /// Global, immutable identifier of the block.
  final BlockId id;

  /// Document this block belongs to.
  final DocumentId doc;

  /// Parent block, `null` for a root block.
  final BlockId? parent;

  /// Fractional index driving the position of the block among its siblings.
  final OrderKey order;

  /// Kind of content of the block.
  final BlockType type;

  /// Textual or rich payload of the block.
  final BlockContent content;

  /// Annotations anchored on this block, keyed by mark identifier.
  final Map<MarkId, MarkRange> marks;

  /// Lamport timestamp of the last modification applied to this block.
  final int lamport;

  /// Author of the last modification applied to this block.
  final AuthorId author;

  /// Whether the block is deleted (tombstone).
  final bool deleted;

  /// Monotonic revision counter of the block.
  final int version;

  /// Whether the block is a tombstone.
  bool get isDeleted => deleted;

  /// Returns a copy of this block with the given fields replaced.
  Block copyWith({
    BlockId? parent,
    OrderKey? order,
    BlockType? type,
    BlockContent? content,
    Map<MarkId, MarkRange>? marks,
    int? lamport,
    AuthorId? author,
    bool? deleted,
    int? version,
  }) {
    return Block(
      id: id,
      doc: doc,
      parent: parent ?? this.parent,
      order: order ?? this.order,
      type: type ?? this.type,
      content: content ?? this.content,
      marks: marks ?? this.marks,
      lamport: lamport ?? this.lamport,
      author: author ?? this.author,
      deleted: deleted ?? this.deleted,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Block &&
          other.id == id &&
          other.doc == doc &&
          other.parent == parent &&
          other.order == order &&
          other.type == type &&
          other.content == content &&
          other.lamport == lamport &&
          other.author == author &&
          other.deleted == deleted &&
          other.version == version &&
          _mapEquals(other.marks, marks));

  @override
  int get hashCode => Object.hash(
    Block,
    id,
    doc,
    parent,
    order,
    type,
    content,
    lamport,
    author,
    deleted,
    version,
    Object.hashAllUnordered(
      marks.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'Block($id, $type, order=$order, v$version)';
}

/// Compares two mark maps for equality, order independent.
bool _mapEquals(Map<MarkId, MarkRange> a, Map<MarkId, MarkRange> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
