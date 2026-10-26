import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/radii.dart';
import 'package:limpid_design_system/src/tokens/spacing.dart';

/// Builds the input decoration theme shared by every text field of the
/// design system.
///
/// The decoration is deliberately flat: a single hairline border that turns
/// into the accent color on focus. It keeps the editorial identity of the
/// product and stays legible in the four themes.
abstract final class LimpidInputDecoration {
  /// Builds the [InputDecorationThemeData] of a palette.
  static InputDecorationThemeData build({
    required LimpidColors colors,
    required TextTheme textTheme,
    required LimpidRadii radii,
    required LimpidSpacing spacing,
  }) {
    final BorderRadius radius = BorderRadius.circular(radii.sm);
    final TextStyle bodyStyle =
        textTheme.bodyMedium ?? const TextStyle(fontSize: 14, height: 22);

    return InputDecorationThemeData(
      filled: true,
      fillColor: colors.bgSurface,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacing.space12,
        vertical: spacing.space12,
      ),
      labelStyle: bodyStyle.copyWith(color: colors.fgMuted),
      floatingLabelStyle: bodyStyle.copyWith(color: colors.accent),
      hintStyle: bodyStyle.copyWith(color: colors.fgSubtle),
      helperStyle: textTheme.labelSmall?.copyWith(color: colors.fgMuted),
      errorStyle: textTheme.labelSmall?.copyWith(color: colors.danger),
      prefixIconColor: colors.fgMuted,
      suffixIconColor: colors.fgMuted,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderSubtle),
      ),
    );
  }
}
