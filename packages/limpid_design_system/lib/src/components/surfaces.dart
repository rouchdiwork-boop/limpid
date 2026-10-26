import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// The elevation levels a [LimpidCard] can use.
enum LimpidCardElevation {
  /// No shadow and no border.
  flat,

  /// A hairline border, no shadow.
  outlined,

  /// The default card shadow.
  raised,

  /// A strong shadow, for the cards that float above the content.
  floating,
}

/// The card of the Limpid design system.
class LimpidCard extends StatelessWidget {
  /// Creates a card.
  const LimpidCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.elevation = LimpidCardElevation.outlined,
    this.padding,
    this.accent,
  });

  /// The content of the card.
  final Widget child;

  /// An optional title displayed above the content.
  final String? title;

  /// An optional secondary line displayed under the title.
  final String? subtitle;

  /// An optional leading widget, usually an icon.
  final Widget? leading;

  /// An optional trailing widget.
  final Widget? trailing;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// The elevation of the card.
  final LimpidCardElevation elevation;

  /// The padding of the card.
  final EdgeInsetsGeometry? padding;

  /// An optional accent strip displayed on the left of the card.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final List<BoxShadow> shadows = switch (elevation) {
      LimpidCardElevation.flat => const <BoxShadow>[],
      LimpidCardElevation.outlined => const <BoxShadow>[],
      LimpidCardElevation.raised => tokens.elevation.level1,
      LimpidCardElevation.floating => tokens.elevation.level2,
    };
    final bool hasBorder = elevation == LimpidCardElevation.outlined;
    // La promotion de type ne s’applique pas aux champs publics : on copie
    // la couleur d’accent dans une variable locale.
    final Color? accentColor = accent;

    final Widget content = Padding(
      padding: padding ?? EdgeInsets.all(tokens.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null || leading != null || trailing != null)
            Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  SizedBox(width: tokens.spacing.space12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (title != null)
                        Text(title!, style: textTheme.titleMedium),
                      if (subtitle != null) ...<Widget>[
                        SizedBox(height: tokens.spacing.space2),
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.colors.fgMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.space12),
                  trailing!,
                ],
              ],
            ),
          if (title != null) SizedBox(height: tokens.spacing.space12),
          child,
        ],
      ),
    );

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        border: hasBorder
            ? Border.all(color: tokens.colors.borderSubtle)
            : accentColor != null
            ? Border(left: BorderSide(width: 4, color: accentColor))
            : null,
        boxShadow: shadows,
      ),
      child: onTap == null
          ? content
          : Material(
              color: LimpidColors.transparent,
              borderRadius: BorderRadius.circular(tokens.radii.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: content),
            ),
    );

    if (accent == null) {
      return Semantics(container: true, button: onTap != null, child: body);
    }

    return Semantics(container: true, button: onTap != null, child: body);
  }
}

/// The list tile of the Limpid design system.
class LimpidListTile extends StatelessWidget {
  /// Creates a list tile.
  const LimpidListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  /// The main label of the tile.
  final String title;

  /// An optional secondary line.
  final String? subtitle;

  /// An optional leading widget.
  final Widget? leading;

  /// An optional trailing widget.
  final Widget? trailing;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  /// Whether the tile is selected.
  final bool selected;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: semanticLabel ?? title,
      selected: selected,
      button: onTap != null,
      child: Material(
        color: selected ? tokens.colors.accentSubtle : LimpidColors.transparent,
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.space16,
              vertical: tokens.spacing.space12,
            ),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  SizedBox(width: tokens.spacing.space12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: textTheme.bodyLarge?.copyWith(
                          color: selected
                              ? tokens.colors.accent
                              : tokens.colors.fgDefault,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        SizedBox(height: tokens.spacing.space2),
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.colors.fgMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.space12),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The direction of a [LimpidStatCard] variation.
enum LimpidStatDirection {
  /// The value went up.
  up,

  /// The value went down.
  down,

  /// The value did not change.
  neutral,
}

/// The statistic card of the Limpid design system.
///
/// It displays a key figure and, optionally, its variation. The variation is
/// carried by an icon and a sign, never by the color alone.
class LimpidStatCard extends StatelessWidget {
  /// Creates a statistic card.
  const LimpidStatCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.direction = LimpidStatDirection.neutral,
    this.icon,
    this.onTap,
    this.caption,
  });

  /// The name of the statistic.
  final String label;

  /// The value of the statistic.
  final String value;

  /// The variation, displayed with a sign.
  final String? delta;

  /// The direction of the variation.
  final LimpidStatDirection direction;

  /// An optional icon.
  final IconData? icon;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// An optional caption displayed under the value.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final Color deltaColor = switch (direction) {
      LimpidStatDirection.up => tokens.colors.success,
      LimpidStatDirection.down => tokens.colors.danger,
      LimpidStatDirection.neutral => tokens.colors.fgMuted,
    };
    final IconData deltaIcon = switch (direction) {
      LimpidStatDirection.up => Icons.arrow_upward,
      LimpidStatDirection.down => Icons.arrow_downward,
      LimpidStatDirection.neutral => Icons.remove,
    };

    return LimpidCard(
      onTap: onTap,
      padding: EdgeInsets.all(tokens.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: tokens.colors.fgMuted),
                SizedBox(width: tokens.spacing.space6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: tokens.colors.fgMuted,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space8),
          Text(
            value,
            style: textTheme.displaySmall?.copyWith(
              color: tokens.colors.fgDefault,
            ),
          ),
          if (delta != null) ...<Widget>[
            SizedBox(height: tokens.spacing.space4),
            Row(
              children: <Widget>[
                Icon(deltaIcon, size: 14, color: deltaColor),
                SizedBox(width: tokens.spacing.space4),
                Text(
                  delta!,
                  style: LimpidTypography.captionStyle(color: deltaColor),
                ),
              ],
            ),
          ],
          if (caption != null) ...<Widget>[
            SizedBox(height: tokens.spacing.space4),
            Text(
              caption!,
              style: LimpidTypography.captionStyle(
                color: tokens.colors.fgSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
