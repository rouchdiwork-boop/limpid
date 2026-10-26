import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'accessibility.dart';

/// A comment anchored on a range of characters of the manuscript.
///
/// The range is expressed in UTF-16 code units of the plain text of the
/// block, the convention used by the editor (see [MarkRange]).
@immutable
class LimpidCommentAnchor {
  /// Creates a comment anchor.
  const LimpidCommentAnchor({
    required this.id,
    required this.range,
    required this.body,
    this.authorName,
    this.isResolved = false,
  });

  /// The identifier of the comment.
  final String id;

  /// The range of the manuscript the comment covers.
  final MarkRange range;

  /// The text of the comment.
  final String body;

  /// The name of the author of the comment.
  final String? authorName;

  /// Whether the comment was resolved.
  final bool isResolved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimpidCommentAnchor &&
          other.id == id &&
          other.range == range &&
          other.body == body &&
          other.authorName == authorName &&
          other.isResolved == isResolved);

  @override
  int get hashCode => Object.hash(id, range, body, authorName, isResolved);
}

/// Returns the style of the text covered by a comment anchor.
///
/// The anchored text is underlined with a dotted line in the secondary
/// colour; when the anchor is hovered, the text also sits on the subtle
/// secondary surface.
///
/// Returns `null` when [offset] is not covered by any anchor.
TextStyle? commentAnchorStyle({
  required TextStyle style,
  required int offset,
  required List<LimpidCommentAnchor> anchors,
  required String? hoveredAnchorId,
  required LimpidColors colors,
}) {
  for (final LimpidCommentAnchor anchor in anchors) {
    if (offset < anchor.range.start || offset >= anchor.range.end) {
      continue;
    }
    final bool isHovered = anchor.id == hoveredAnchorId;
    return style.copyWith(
      color: colors.secondary,
      backgroundColor: isHovered ? colors.secondarySubtle : null,
      decoration: TextDecoration.underline,
      decorationColor: colors.secondary,
      decorationStyle: TextDecorationStyle.dotted,
    );
  }
  return null;
}

/// The list of the comments anchored on the manuscript.
///
/// Selecting a comment hands the anchored range over to the editor, which
/// moves the selection there.
class LimpidCommentAnchors extends StatelessWidget {
  /// Creates the list of comment anchors.
  const LimpidCommentAnchors({
    super.key,
    required this.anchors,
    required this.onSelect,
    this.onHover,
    this.hoveredAnchorId,
  });

  /// The comments anchored on the manuscript.
  final List<LimpidCommentAnchor> anchors;

  /// Called when the author selects a comment.
  final ValueChanged<LimpidCommentAnchor> onSelect;

  /// Called when the pointer enters or leaves a comment.
  final ValueChanged<String?>? onHover;

  /// The identifier of the hovered comment.
  final String? hoveredAnchorId;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (anchors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      label: 'Commentaires du manuscrit',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final LimpidCommentAnchor anchor in anchors)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.space8),
              child: _LimpidCommentAnchorChip(
                anchor: anchor,
                isHovered: anchor.id == hoveredAnchorId,
                onTap: () => onSelect(anchor),
                onHover: onHover,
                textTheme: textTheme,
              ),
            ),
        ],
      ),
    );
  }
}

class _LimpidCommentAnchorChip extends StatelessWidget {
  const _LimpidCommentAnchorChip({
    required this.anchor,
    required this.isHovered,
    required this.onTap,
    required this.onHover,
    required this.textTheme,
  });

  final LimpidCommentAnchor anchor;
  final bool isHovered;
  final VoidCallback onTap;
  final ValueChanged<String?>? onHover;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return Semantics(
      button: true,
      label: anchor.authorName ?? 'Commentaire',
      hint: anchor.body,
      child: MouseRegion(
        onEnter: (PointerEnterEvent _) => onHover?.call(anchor.id),
        onExit: (PointerExitEvent _) => onHover?.call(null),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinimumTapTarget),
          child: Material(
            color: isHovered
                ? tokens.colors.secondarySubtle
                : tokens.colors.bgSurface,
            borderRadius: BorderRadius.circular(tokens.radii.sm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(tokens.radii.sm),
              child: Container(
                padding: EdgeInsets.all(tokens.spacing.space8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radii.sm),
                  border: Border.all(
                    color: isHovered
                        ? tokens.colors.secondary
                        : tokens.colors.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      LimpidIcons.comment,
                      size: 16,
                      color: tokens.colors.secondary,
                    ),
                    SizedBox(width: tokens.spacing.space8),
                    Flexible(
                      child: Text(
                        anchor.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
