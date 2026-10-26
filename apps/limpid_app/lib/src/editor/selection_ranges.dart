import 'package:flutter/foundation.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// The passage of the manuscript the author selected, brought back to its
/// block.
///
/// The range is expressed in the coordinates of the **block**: they are the
/// ones the marks of the CRDT use (see `MarkRange`), and the ones the anchor
/// of a discussion is computed from.
@immutable
class SelectedPassage {
  /// Creates a passage.
  const SelectedPassage({
    required this.blockId,
    required this.range,
    required this.text,
  });

  /// The block the passage belongs to.
  final BlockId blockId;

  /// The range of the passage inside its block.
  final MarkRange range;

  /// The words the author selected.
  final String text;

  /// The number of words of the passage.
  int get length => text.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelectedPassage &&
          other.blockId == blockId &&
          other.range == range &&
          other.text == text);

  @override
  int get hashCode => Object.hash(blockId, range, text);

  @override
  String toString() => 'SelectedPassage($blockId, $range)';
}

/// The passage the selection `start`..`end` covers, `null` when it holds
/// nothing.
///
/// The selection of the editor is an offset in the document of the scene:
/// the blocks are laid out one after the other, each of them followed by its
/// newline. The function walks the blocks and returns the range the
/// selection covers **inside** the block it belongs to.
///
/// The selection is refused when it crosses two blocks: a comment is
/// anchored on a single block, and a range that spans two of them would
/// cover words that do not belong to the same paragraph.
SelectedPassage? selectedPassageOf({
  required List<SceneBlock> blocks,
  required int start,
  required int end,
}) {
  if (end <= start) {
    return null;
  }
  int offset = 0;
  for (final SceneBlock block in blocks) {
    final int length = block.plainText.length;
    final int blockStart = offset;
    final int blockEnd = blockStart + length;
    offset = blockEnd + 1;
    if (start < blockStart || start >= blockEnd) {
      continue;
    }
    if (end > blockEnd) {
      return null;
    }
    final int from = start - blockStart;
    final int to = end - blockStart;
    if (to <= from) {
      return null;
    }
    return SelectedPassage(
      blockId: block.id,
      range: MarkRange(start: from, end: to),
      text: block.plainText.substring(from, to),
    );
  }
  return null;
}
