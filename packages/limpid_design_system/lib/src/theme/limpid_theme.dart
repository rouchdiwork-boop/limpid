import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_component_themes.dart';
import 'package:limpid_design_system/src/theme/limpid_input_decoration.dart';
import 'package:limpid_design_system/src/theme/limpid_theme_scope.dart';
import 'package:limpid_design_system/src/theme/limpid_theme_variant.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/radii.dart';
import 'package:limpid_design_system/src/tokens/spacing.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

export 'package:limpid_design_system/src/theme/limpid_theme_scope.dart'
    show LimpidThemeContext, LimpidThemeScope;
export 'package:limpid_design_system/src/theme/limpid_theme_variant.dart'
    show LimpidThemeVariant, LimpidThemeVariantTokens;

/// Builds the four themes of the Limpid design system.
///
/// ```dart
/// MaterialApp(
///   theme: LimpidTheme.of(LimpidThemeVariant.paper),
///   darkTheme: LimpidTheme.of(LimpidThemeVariant.night),
///   home: const HomePage(),
/// );
/// ```
abstract final class LimpidTheme {
  /// Alpha of the focus overlay.
  static const double _focusAlpha = 0.16;

  /// Alpha of the hover overlay.
  static const double _hoverAlpha = 0.06;

  /// Alpha of the press overlay.
  static const double _highlightAlpha = 0.10;

  /// Alpha of the splash overlay.
  static const double _splashAlpha = 0.12;

  /// Default size of an icon, in logical pixels.
  static const double _iconSize = 20;

  /// Builds the complete [ThemeData] of a variant.
  ///
  /// The returned theme carries the color scheme, the text theme and every
  /// component theme of the design system, and registers the token scopes
  /// reachable with `context.limpid`.
  static ThemeData of(LimpidThemeVariant variant) => _build(variant);

  /// Returns the theme of the closest [Theme] ancestor.
  static ThemeData ofContext(BuildContext context) => Theme.of(context);

  static ThemeData _build(LimpidThemeVariant variant) {
    final LimpidColors colors = variant.colors;
    final ColorScheme scheme = colors.toColorScheme();
    final TextTheme textTheme = LimpidTypography.buildTextTheme(
      primary: colors.fgDefault,
      secondary: colors.fgMuted,
    );
    final LimpidThemeInput input = LimpidThemeInput(
      colors: colors,
      textTheme: textTheme,
      radii: const LimpidRadii(),
      spacing: const LimpidSpacing(),
      isDark: variant.isDark,
    );
    final LimpidThemeScope scope = LimpidThemeScope(
      variant: variant,
      colors: colors,
      elevation: variant.elevation,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.bgCanvas,
      canvasColor: colors.bgCanvas,
      cardColor: colors.bgSurface,
      dividerColor: colors.borderSubtle,
      disabledColor: colors.fgSubtle,
      hintColor: colors.fgMuted,
      shadowColor: colors.shadowTone,
      focusColor: colors.accent.withValues(alpha: _focusAlpha),
      hoverColor: colors.accent.withValues(alpha: _hoverAlpha),
      highlightColor: colors.accent.withValues(alpha: _highlightAlpha),
      splashColor: colors.accent.withValues(alpha: _splashAlpha),
      unselectedWidgetColor: colors.borderStrong,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: colors.fgDefault, size: _iconSize),
      primaryIconTheme: IconThemeData(
        color: colors.fgOnAccent,
        size: _iconSize,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[colors, variant.elevation, scope],
      appBarTheme: LimpidComponentThemes.appBar(input),
      cardTheme: LimpidComponentThemes.card(input),
      dialogTheme: LimpidComponentThemes.dialog(input),
      bottomSheetTheme: LimpidComponentThemes.bottomSheet(input),
      drawerTheme: LimpidComponentThemes.drawer(input),
      snackBarTheme: LimpidComponentThemes.snackBar(input),
      tooltipTheme: LimpidComponentThemes.tooltip(input),
      dividerTheme: LimpidComponentThemes.divider(input),
      popupMenuTheme: LimpidComponentThemes.popupMenu(input),
      tabBarTheme: LimpidComponentThemes.tabBar(input),
      listTileTheme: LimpidComponentThemes.listTile(input),
      chipTheme: LimpidComponentThemes.chip(input),
      checkboxTheme: LimpidComponentThemes.checkbox(input),
      radioTheme: LimpidComponentThemes.radio(input),
      switchTheme: LimpidComponentThemes.switchTheme(input),
      sliderTheme: LimpidComponentThemes.slider(input),
      segmentedButtonTheme: LimpidComponentThemes.segmentedButton(input),
      iconButtonTheme: LimpidComponentThemes.iconButton(input),
      dataTableTheme: LimpidComponentThemes.dataTable(input),
      progressIndicatorTheme: LimpidComponentThemes.progressIndicator(input),
      textSelectionTheme: LimpidComponentThemes.textSelection(input),
      inputDecorationTheme: LimpidInputDecoration.build(
        colors: colors,
        textTheme: textTheme,
        radii: input.radii,
        spacing: input.spacing,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
