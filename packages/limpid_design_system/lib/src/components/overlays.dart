import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The tooltip of the Limpid design system.
///
/// It only carries the behavior: the decoration comes from the theme built
/// by `LimpidTheme.of`.
class LimpidTooltip extends StatelessWidget {
  /// Creates a tooltip.
  const LimpidTooltip({
    super.key,
    required this.message,
    required this.child,
    this.excludeFromSemantics = false,
  });

  /// The text displayed in the tooltip.
  final String message;

  /// The widget the tooltip is attached to.
  final Widget child;

  /// Whether the tooltip is hidden from screen readers.
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      excludeFromSemantics: excludeFromSemantics,
      child: child,
    );
  }
}

/// An entry of a [LimpidMenu].
@immutable
class LimpidMenuItem {
  /// Creates a menu item.
  const LimpidMenuItem({
    required this.label,
    required this.value,
    this.icon,
    this.isEnabled = true,
    this.isDestructive = false,
  });

  /// The text of the item.
  final String label;

  /// The value returned when the item is picked.
  final Object value;

  /// An optional leading icon.
  final IconData? icon;

  /// Whether the item can be picked.
  final bool isEnabled;

  /// Whether the item carries a destructive action.
  final bool isDestructive;

  @override
  String toString() => 'LimpidMenuItem($label)';
}

/// The pop-up menu of the Limpid design system.
class LimpidMenu extends StatelessWidget {
  /// Creates a menu.
  ///
  /// Either [child] or [label] must be provided: a menu always needs a
  /// visible trigger.
  const LimpidMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.child,
    this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
  }) : assert(
         child != null || label != null,
         'A LimpidMenu needs a trigger: provide a child or a label.',
       );

  /// The entries of the menu.
  final List<LimpidMenuItem> items;

  /// Called when an entry is picked.
  final ValueChanged<LimpidMenuItem> onSelected;

  /// A custom trigger widget.
  final Widget? child;

  /// The text of the default trigger.
  final String? label;

  /// The icon of the default trigger.
  final IconData? icon;

  /// The tooltip of the default trigger.
  final String? tooltip;

  /// Whether the menu can be opened.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final Widget? trigger = child ?? _buildLabelTrigger(context);

    return PopupMenuButton<LimpidMenuItem>(
      onSelected: onSelected,
      tooltip: tooltip,
      enabled: enabled,
      icon: trigger == null ? Icon(icon ?? LimpidIcons.more) : null,
      color: tokens.colors.bgRaised,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.md),
        side: BorderSide(color: tokens.colors.borderSubtle),
      ),
      itemBuilder: (BuildContext context) => items
          .map(
            (LimpidMenuItem item) => PopupMenuItem<LimpidMenuItem>(
              value: item,
              enabled: item.isEnabled,
              child: Row(
                children: <Widget>[
                  if (item.icon != null) ...<Widget>[
                    Icon(
                      item.icon,
                      size: 18,
                      color: item.isDestructive
                          ? tokens.colors.danger
                          : tokens.colors.fgMuted,
                    ),
                    SizedBox(width: tokens.spacing.space12),
                  ],
                  Text(
                    item.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: item.isDestructive
                          ? tokens.colors.danger
                          : tokens.colors.fgDefault,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: trigger,
    );
  }

  Widget? _buildLabelTrigger(BuildContext context) {
    final String? text = label;
    if (text == null) {
      return null;
    }
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18),
          SizedBox(width: tokens.spacing.space8),
        ],
        Text(text, style: textTheme.bodyMedium),
      ],
    );
  }
}
