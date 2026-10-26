import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// The size of the icons of the band, in logical pixels.
const double _kIconSize = 16;

/// The passage of the manuscript the selected comment points at.
///
/// The band sits above the manuscript and shows the passage in relief, with
/// the very style the editor gives to the anchors of the comments: the
/// secondary colour, a dotted underline and the subtle surface behind.
class WritingSelectedPassage extends StatelessWidget {
  /// Creates the band of a passage.
  const WritingSelectedPassage({
    required this.anchor,
    required this.excerpt,
    required this.onClose,
    super.key,
  });

  /// The anchor the passage comes from.
  final LimpidCommentAnchor anchor;

  /// The text of the passage.
  final String excerpt;

  /// Called when the author closes the band.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle? style = commentAnchorStyle(
      style: textTheme.bodyMedium ?? const TextStyle(),
      offset: anchor.range.start,
      anchors: <LimpidCommentAnchor>[anchor],
      hoveredAnchorId: anchor.id,
      colors: tokens.colors,
    );

    return Container(
      margin: EdgeInsets.symmetric(horizontal: tokens.spacing.space24),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.space12,
        vertical: tokens.spacing.space8,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        border: Border.all(color: tokens.colors.secondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            LimpidIcons.comment,
            size: _kIconSize,
            color: tokens.colors.secondary,
          ),
          SizedBox(width: tokens.spacing.space8),
          Expanded(
            child: Text(
              excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: style ?? textTheme.bodyMedium,
            ),
          ),
          Semantics(
            button: true,
            label: strings.actionCancel,
            child: IconButton(
              onPressed: onClose,
              tooltip: null,
              icon: Icon(
                LimpidIcons.close,
                size: _kIconSize,
                color: tokens.colors.fgMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
