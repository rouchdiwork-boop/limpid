import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/components/buttons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';

/// An icon only button of the Limpid design system.
///
/// The hit area is always at least 44×44 logical pixels and a tooltip is
/// mandatory: an icon alone is never enough to convey a meaning.
class LimpidIconButton extends StatelessWidget {
  /// Creates an icon button.
  const LimpidIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = LimpidButtonVariant.ghost,
    this.size = LimpidButtonSize.medium,
    this.color,
  });

  /// The icon to display.
  final IconData icon;

  /// The tooltip of the button, also used as its semantic label.
  final String tooltip;

  /// Called when the button is pressed. A null callback disables it.
  final VoidCallback? onPressed;

  /// The visual variant.
  final LimpidButtonVariant variant;

  /// The size of the button.
  final LimpidButtonSize size;

  /// An optional color override for the icon.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidColors colors = tokens.colors;

    final double dimension = switch (size) {
      LimpidButtonSize.small => 32,
      LimpidButtonSize.medium => 40,
      LimpidButtonSize.large => 48,
    };
    final double iconSize = switch (size) {
      LimpidButtonSize.small => 16,
      LimpidButtonSize.medium => 20,
      LimpidButtonSize.large => 24,
    };

    final bool isFilled =
        variant == LimpidButtonVariant.primary ||
        variant == LimpidButtonVariant.secondary ||
        variant == LimpidButtonVariant.danger;

    final Color background = switch (variant) {
      LimpidButtonVariant.primary => colors.accent,
      LimpidButtonVariant.secondary => colors.secondary,
      LimpidButtonVariant.danger => colors.danger,
      LimpidButtonVariant.ghost ||
      LimpidButtonVariant.text => LimpidColors.transparent,
    };
    final Color foreground = switch (variant) {
      LimpidButtonVariant.primary => colors.fgOnAccent,
      LimpidButtonVariant.secondary => colors.fgOnAccent,
      LimpidButtonVariant.danger => colors.fgOnAccent,
      LimpidButtonVariant.ghost || LimpidButtonVariant.text => colors.fgDefault,
    };

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: IconButton(
          onPressed: onPressed,
          tooltip: null,
          iconSize: iconSize,
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll<Size>(Size.square(dimension)),
            fixedSize: WidgetStatePropertyAll<Size?>(Size.square(dimension)),
            backgroundColor: WidgetStatePropertyAll<Color?>(
              isFilled ? background : LimpidColors.transparent,
            ),
            foregroundColor: WidgetStatePropertyAll<Color?>(
              color ?? foreground,
            ),
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radii.sm),
              ),
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}
