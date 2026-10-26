import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// The semantic status variants of the design system.
///
/// A status is always carried by a color, an icon and a text: the color
/// alone never carries the meaning (WCAG 2.2, 1.4.1).
enum LimpidStatusVariant {
  /// A neutral status, without any particular meaning.
  neutral,

  /// An informational status.
  info,

  /// A successful status.
  success,

  /// A warning status.
  warning,

  /// An error status.
  danger,
}

/// The colors and the icon of a status variant.
@immutable
class LimpidStatusStyle {
  /// Creates a status style.
  const LimpidStatusStyle({
    required this.color,
    required this.icon,
    required this.background,
  });

  /// The foreground color of the status.
  final Color color;

  /// The icon of the status.
  final IconData icon;

  /// The background color of the status.
  final Color background;

  /// Builds the style of a variant for a given palette.
  factory LimpidStatusStyle.of(
    LimpidStatusVariant variant,
    LimpidColors colors,
  ) {
    final Color tone = switch (variant) {
      LimpidStatusVariant.neutral => colors.fgMuted,
      LimpidStatusVariant.info => colors.info,
      LimpidStatusVariant.success => colors.success,
      LimpidStatusVariant.warning => colors.warning,
      LimpidStatusVariant.danger => colors.danger,
    };
    final IconData icon = switch (variant) {
      LimpidStatusVariant.neutral => LimpidIcons.neutral,
      LimpidStatusVariant.info => LimpidIcons.info,
      LimpidStatusVariant.success => LimpidIcons.success,
      LimpidStatusVariant.warning => LimpidIcons.warning,
      LimpidStatusVariant.danger => LimpidIcons.danger,
    };
    return LimpidStatusStyle(
      color: tone,
      icon: icon,
      background: Color.alphaBlend(
        tone.withValues(alpha: 0.12),
        colors.bgSurface,
      ),
    );
  }
}

/// The small status pill of the Limpid design system.
class LimpidBadge extends StatelessWidget {
  /// Creates a badge.
  const LimpidBadge({
    super.key,
    required this.label,
    this.variant = LimpidStatusVariant.neutral,
    this.icon,
    this.showDot = false,
  });

  /// The text of the badge.
  final String label;

  /// The status carried by the badge.
  final LimpidStatusVariant variant;

  /// An optional icon. When null, the icon of the variant is used.
  final IconData? icon;

  /// Whether the badge displays a dot instead of an icon.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidStatusStyle style = LimpidStatusStyle.of(
      variant,
      tokens.colors,
    );

    return Semantics(
      label: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.space8,
          vertical: tokens.spacing.space4,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          border: Border.all(color: style.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showDot)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: style.color,
                  shape: BoxShape.circle,
                ),
              )
            else
              Icon(icon ?? style.icon, size: 14, color: style.color),
            SizedBox(width: tokens.spacing.space6),
            // Le libellé peut être plus long que la place disponible dans une
            // carte étroite : il doit se tronquer plutôt que déborder.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LimpidTypography.token(
                  'label',
                ).toStyle(color: style.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The interactive chip of the Limpid design system.
///
/// A chip filters, selects or removes an item. It is never used to carry a
/// status: use a [LimpidBadge] for that.
class LimpidChip extends StatelessWidget {
  /// Creates a chip.
  const LimpidChip({
    super.key,
    required this.label,
    this.onTap,
    this.onDeleted,
    this.icon,
    this.isSelected = false,
    this.deleteTooltip = 'Retirer',
    this.semanticLabel,
  });

  /// The text of the chip.
  final String label;

  /// Called when the chip is tapped.
  final VoidCallback? onTap;

  /// Called when the chip is removed.
  final VoidCallback? onDeleted;

  /// An optional leading icon.
  final IconData? icon;

  /// Whether the chip is selected.
  final bool isSelected;

  /// The tooltip of the delete button.
  final String deleteTooltip;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextStyle labelStyle = LimpidTypography.token('label').toStyle(
      color: isSelected ? tokens.colors.accent : tokens.colors.fgDefault,
    );

    return Semantics(
      label: semanticLabel ?? label,
      button: onTap != null,
      selected: isSelected,
      child: Material(
        color: isSelected ? tokens.colors.accentSubtle : tokens.colors.bgSunken,
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected
                ? tokens.colors.accentBorder
                : tokens.colors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.space12,
              vertical: tokens.spacing.space6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? tokens.colors.accent
                        : tokens.colors.fgMuted,
                  ),
                  SizedBox(width: tokens.spacing.space6),
                ],
                Text(label, style: labelStyle),
                if (onDeleted != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.space4),
                  Semantics(
                    button: true,
                    label: deleteTooltip,
                    child: InkWell(
                      onTap: onDeleted,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          LimpidIcons.close,
                          size: 14,
                          color: tokens.colors.fgMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The static tag of the Limpid design system.
///
/// A tag labels a piece of content (a genre, a status, a chapter). Unlike a
/// chip, it is never interactive.
class LimpidTag extends StatelessWidget {
  /// Creates a tag.
  const LimpidTag({
    super.key,
    required this.label,
    this.icon,
    this.variant = LimpidStatusVariant.neutral,
  });

  /// The text of the tag.
  final String label;

  /// An optional leading icon.
  final IconData? icon;

  /// The status carried by the tag.
  final LimpidStatusVariant variant;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidStatusStyle style = LimpidStatusStyle.of(
      variant,
      tokens.colors,
    );

    return Semantics(
      label: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.space8,
          vertical: tokens.spacing.space2,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(tokens.radii.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 12, color: style.color),
              SizedBox(width: tokens.spacing.space4),
            ],
            Text(
              label,
              style: LimpidTypography.token(
                'caption',
              ).toStyle(color: style.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status banner of the Limpid design system.
///
/// A banner always carries a color, an icon and a text so that the
/// information never depends on the color alone.
class LimpidBanner extends StatelessWidget {
  /// Creates a banner.
  const LimpidBanner({
    super.key,
    required this.variant,
    required this.title,
    this.message,
    this.action,
    this.onDismiss,
    this.dismissTooltip = 'Fermer',
  });

  /// The status carried by the banner.
  final LimpidStatusVariant variant;

  /// The title of the banner.
  final String title;

  /// An optional secondary line.
  final String? message;

  /// An optional action displayed on the right.
  final Widget? action;

  /// Called when the banner is dismissed.
  final VoidCallback? onDismiss;

  /// The tooltip of the dismiss button.
  final String dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidStatusStyle style = LimpidStatusStyle.of(
      variant,
      tokens.colors,
    );
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label: message == null ? title : '$title. $message',
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.space16),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(tokens.radii.md),
          border: Border.all(color: style.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(style.icon, size: 20, color: style.color),
            SizedBox(width: tokens.spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.colors.fgDefault,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (message != null) ...<Widget>[
                    SizedBox(height: tokens.spacing.space4),
                    Text(
                      message!,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.colors.fgMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...<Widget>[
              SizedBox(width: tokens.spacing.space12),
              action!,
            ],
            if (onDismiss != null) ...<Widget>[
              SizedBox(width: tokens.spacing.space8),
              Semantics(
                button: true,
                label: dismissTooltip,
                child: IconButton(
                  onPressed: onDismiss,
                  tooltip: null,
                  icon: Icon(
                    LimpidIcons.close,
                    size: 18,
                    color: tokens.colors.fgMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
