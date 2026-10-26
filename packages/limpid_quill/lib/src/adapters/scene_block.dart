import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:limpid_core/limpid_core.dart';

/// The origin of an editor line that a change created.
const int kNewLineOrigin = -1;

/// A block of a scene document: the CRDT projection of one line of the
/// manuscript editor.
///
/// A scene is the atomic unit of storage and of synchronisation (D-02): it
/// owns one CRDT document, and that document holds a tree of blocks. This
/// class models the *content* blocks of the tree — the paragraphs, the
/// headings, the lists — the ones the editor manipulates line by line.
@immutable
class SceneBlock {
  /// Creates a scene block.
  const SceneBlock({
    required this.id,
    required this.type,
    required this.content,
    required this.order,
    this.parent,
  });

  /// The global identifier of the block.
  final BlockId id;

  /// The kind of content held by the block.
  final BlockType type;

  /// The textual or rich payload of the block.
  final BlockContent content;

  /// The fractional index of the block among its siblings.
  final OrderKey order;

  /// The parent block, `null` when the block is a root block.
  final BlockId? parent;

  /// The plain text projection of the content.
  String get plainText => content.plainText;

  /// Returns a copy of this block with the given fields replaced.
  SceneBlock copyWith({
    BlockType? type,
    BlockContent? content,
    OrderKey? order,
    BlockId? parent,
  }) {
    return SceneBlock(
      id: id,
      type: type ?? this.type,
      content: content ?? this.content,
      order: order ?? this.order,
      parent: parent ?? this.parent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneBlock &&
          other.id == id &&
          other.type == type &&
          other.content == content &&
          other.order == order &&
          other.parent == parent);

  @override
  int get hashCode => Object.hash(id, type, content, order, parent);

  @override
  String toString() => 'SceneBlock($id, $type)';
}

/// The state of a scene document: the editor document and the CRDT blocks
/// backing its lines.
@immutable
class SceneEditorState {
  /// Creates a scene editor state.
  const SceneEditorState({required this.document, required this.blocks});

  /// The editor document, as a Quill delta.
  final Delta document;

  /// The CRDT blocks backing the lines of the document, in order.
  final List<SceneBlock> blocks;

  /// Returns a copy of this state with the given fields replaced.
  SceneEditorState copyWith({Delta? document, List<SceneBlock>? blocks}) {
    return SceneEditorState(
      document: document ?? this.document,
      blocks: blocks ?? this.blocks,
    );
  }
}
