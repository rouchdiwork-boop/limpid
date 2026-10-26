import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'comment_anchors.dart';

/// The opacity of the lines that are not focused, in the focus mode
/// (DESIGN_SYSTEM § 11.1).
const double kFocusDimOpacity = 0.45;

/// Returns the range of the line holding [offset] in [document].
///
/// The range covers the newline of the line; it is `null` when the
/// document is empty.
(int, int)? editorLineRangeAt(Document document, int offset) {
  final int length = document.length;
  if (length <= 0) {
    return null;
  }
  final int clamped = offset.clamp(0, length - 1);
  final Leaf? leaf = document.querySegmentLeafNode(clamped).leaf;
  final line = leaf?.parent;
  if (line == null) {
    return null;
  }
  final int start = line.documentOffset;
  return (start, start + line.length);
}

/// Builds the spans of the manuscript.
///
/// The builder dims the lines that are not focused in the focus mode and
/// decorates the ranges covered by a comment anchor.
@immutable
class LimpidEditorSpanBuilder {
  /// Creates a span builder.
  const LimpidEditorSpanBuilder({
    required this.colors,
    required this.isFocusMode,
    required this.activeLineStart,
    required this.activeLineEnd,
    required this.anchors,
    required this.hoveredAnchorId,
  });

  /// The colour palette of the active theme.
  final LimpidColors colors;

  /// Whether the lines that are not focused are dimmed.
  final bool isFocusMode;

  /// The offset of the first character of the focused line.
  final int? activeLineStart;

  /// The offset of the end of the focused line.
  final int? activeLineEnd;

  /// The comments anchored on the manuscript.
  final List<LimpidCommentAnchor> anchors;

  /// The identifier of the hovered comment.
  final String? hoveredAnchorId;

  /// Builds the span of a leaf of the editor.
  InlineSpan build(
    BuildContext context,
    Node node,
    int offset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    final int documentOffset = node.documentOffset + offset;
    TextStyle? effective = style;
    if (isFocusMode && !isInActiveLine(documentOffset)) {
      effective = effective?.copyWith(
        color: colors.fgDefault.withValues(alpha: kFocusDimOpacity),
      );
    }
    final TextStyle? anchored = commentAnchorStyle(
      style: effective ?? const TextStyle(),
      offset: documentOffset,
      anchors: anchors,
      hoveredAnchorId: hoveredAnchorId,
      colors: colors,
    );
    if (anchored != null) {
      effective = anchored;
    }
    return defaultSpanBuilder(
      context,
      node,
      offset,
      text,
      effective,
      recognizer,
    );
  }

  /// Whether [offset] belongs to the focused line.
  bool isInActiveLine(int offset) {
    final int? start = activeLineStart;
    final int? end = activeLineEnd;
    if (start == null || end == null) {
      return true;
    }
    return offset >= start && offset < end;
  }
}
