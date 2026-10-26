import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme_variant.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/elevation.dart';
import 'package:limpid_design_system/src/tokens/motion.dart';
import 'package:limpid_design_system/src/tokens/radii.dart';
import 'package:limpid_design_system/src/tokens/spacing.dart';

/// Every design token of the active theme, in a single immutable object.
///
/// The scope is registered as a [ThemeExtension] by [LimpidTheme.of] and is
/// reachable from any widget with `context.limpid`.
@immutable
class LimpidThemeScope extends ThemeExtension<LimpidThemeScope> {
  /// Creates a theme scope.
  const LimpidThemeScope({
    required this.variant,
    required this.colors,
    required this.elevation,
    this.spacing = const LimpidSpacing(),
    this.radii = const LimpidRadii(),
    this.motion = const LimpidMotion(),
  });

  /// The active theme variant.
  final LimpidThemeVariant variant;

  /// The color palette of the active variant.
  final LimpidColors colors;

  /// The elevation scale of the active variant.
  final LimpidElevation elevation;

  /// The spacing scale.
  final LimpidSpacing spacing;

  /// The radius scale.
  final LimpidRadii radii;

  /// The motion scale.
  final LimpidMotion motion;

  /// Whether the active variant is a dark one.
  bool get isDark => variant.isDark;

  @override
  LimpidThemeScope copyWith() => this;

  @override
  LimpidThemeScope lerp(
    covariant ThemeExtension<LimpidThemeScope>? other,
    double t,
  ) {
    if (other is! LimpidThemeScope) {
      return this;
    }
    return LimpidThemeScope(
      variant: t < 0.5 ? variant : other.variant,
      colors: colors.lerp(other.colors, t),
      elevation: elevation.lerp(other.elevation, t),
      spacing: spacing,
      radii: radii,
      motion: motion,
    );
  }
}

/// Gives access to the design tokens of the active theme.
///
/// ```dart
/// Container(
///   padding: EdgeInsets.all(context.limpid.spacing.space16),
///   decoration: BoxDecoration(
///     color: context.limpid.colors.bgSurface,
///     borderRadius: BorderRadius.circular(context.limpid.radii.md),
///   ),
/// );
/// ```
extension LimpidThemeContext on BuildContext {
  /// The design tokens of the active theme.
  ///
  /// Throws a [FlutterError] when the widget tree is not wrapped in a theme
  /// built by `LimpidTheme.of`.
  LimpidThemeScope get limpid {
    final ThemeData theme = Theme.of(this);
    final LimpidThemeScope? scope = theme.extension<LimpidThemeScope>();
    if (scope == null) {
      throw FlutterError(
        'No LimpidThemeScope found in the widget tree.\n'
        'Wrap your application in a MaterialApp built with '
        'LimpidTheme.of(LimpidThemeVariant.paper) (or another variant).',
      );
    }
    return scope;
  }
}
