import 'package:flutter/material.dart';

/// The canonical color tokens of the Limpid design system.
///
/// The class is a [ThemeExtension]: the palette of the active variant is
/// reachable with `Theme.of(context).extension<LimpidColors>()` or, more
/// conveniently, with `context.limpid.colors`.
///
/// Four palettes are shipped: `paper` (default), `sepia`, `night` (dark) and
/// `contrast` (WCAG AAA). No component is allowed to inline a literal color:
/// everything comes from this file.
@immutable
class LimpidColors extends ThemeExtension<LimpidColors> {
  /// Creates a color palette. Every token must be provided explicitly.
  const LimpidColors({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgRaised,
    required this.bgSunken,
    required this.fgDefault,
    required this.fgMuted,
    required this.fgSubtle,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSubtle,
    required this.accentBorder,
    required this.fgOnAccent,
    required this.secondary,
    required this.secondarySubtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  /// The `paper` palette — the default working theme.
  static const LimpidColors paper = LimpidColors(
    bgCanvas: Color(0xFFFAF8F4),
    bgSurface: Color(0xFFFFFFFF),
    bgRaised: Color(0xFFFFFFFF),
    bgSunken: Color(0xFFF2EEE6),
    fgDefault: Color(0xFF16130F),
    fgMuted: Color(0xFF57504A),
    fgSubtle: Color(0xFF857C72),
    borderSubtle: Color(0xFFE7E1D6),
    borderDefault: Color(0xFFD8D0C2),
    borderStrong: Color(0xFFBCB2A0),
    accent: Color(0xFF9C5518),
    accentHover: Color(0xFF83450F),
    accentPressed: Color(0xFF6E3909),
    accentSubtle: Color(0xFFF6E7D6),
    accentBorder: Color(0xFFE4C4A0),
    fgOnAccent: Color(0xFFFFFFFF),
    secondary: Color(0xFF35407E),
    secondarySubtle: Color(0xFFE8EAF7),
    success: Color(0xFF3E6B4F),
    warning: Color(0xFF8A6410),
    danger: Color(0xFFA8341F),
    info: Color(0xFF2E5F7A),
  );

  /// The `sepia` palette — a warm, long-reading theme.
  static const LimpidColors sepia = LimpidColors(
    bgCanvas: Color(0xFFF4EBD8),
    bgSurface: Color(0xFFFBF6EA),
    bgRaised: Color(0xFFFFFDF8),
    bgSunken: Color(0xFFE9DEC6),
    fgDefault: Color(0xFF33281A),
    fgMuted: Color(0xFF6B5C48),
    fgSubtle: Color(0xFF8C7C64),
    borderSubtle: Color(0xFFDFD3B8),
    borderDefault: Color(0xFFCDBFA0),
    borderStrong: Color(0xFFB3A184),
    accent: Color(0xFF8E4A12),
    accentHover: Color(0xFF763C0B),
    accentPressed: Color(0xFF633207),
    accentSubtle: Color(0xFFF0E0C8),
    accentBorder: Color(0xFFDCBC93),
    fgOnAccent: Color(0xFFFFFFFF),
    secondary: Color(0xFF2F3A72),
    secondarySubtle: Color(0xFFE4E7F5),
    success: Color(0xFF356043),
    warning: Color(0xFF7A5810),
    danger: Color(0xFF97301C),
    info: Color(0xFF28566F),
  );

  /// The `night` palette — the dark writing theme.
  static const LimpidColors night = LimpidColors(
    bgCanvas: Color(0xFF14110E),
    bgSurface: Color(0xFF1C1915),
    bgRaised: Color(0xFF242019),
    bgSunken: Color(0xFF0F0D0A),
    fgDefault: Color(0xFFF0EBE2),
    fgMuted: Color(0xFFA79E92),
    fgSubtle: Color(0xFF7A7268),
    borderSubtle: Color(0xFF2B261F),
    borderDefault: Color(0xFF3A332A),
    borderStrong: Color(0xFF4C4438),
    accent: Color(0xFFE0A460),
    accentHover: Color(0xFFF0BC85),
    accentPressed: Color(0xFFC98E4A),
    accentSubtle: Color(0xFF2E2418),
    accentBorder: Color(0xFF4A3A22),
    fgOnAccent: Color(0xFF1A1207),
    secondary: Color(0xFF9BA4E8),
    secondarySubtle: Color(0xFF1E2138),
    success: Color(0xFF7FB093),
    warning: Color(0xFFD9A845),
    danger: Color(0xFFE08573),
    info: Color(0xFF7FB3CE),
  );

  /// The `contrast` palette — WCAG AAA on pure black and white.
  static const LimpidColors contrast = LimpidColors(
    bgCanvas: Color(0xFF000000),
    bgSurface: Color(0xFF000000),
    bgRaised: Color(0xFF0A0A0A),
    bgSunken: Color(0xFF000000),
    fgDefault: Color(0xFFFFFFFF),
    fgMuted: Color(0xFFFFFFFF),
    fgSubtle: Color(0xFFE6E6E6),
    borderSubtle: Color(0xFFFFFFFF),
    borderDefault: Color(0xFFFFFFFF),
    borderStrong: Color(0xFFFFFFFF),
    accent: Color(0xFFFFB454),
    accentHover: Color(0xFFFFC87A),
    accentPressed: Color(0xFFD99338),
    accentSubtle: Color(0xFF2A2013),
    accentBorder: Color(0xFF6B5223),
    fgOnAccent: Color(0xFF000000),
    secondary: Color(0xFFAEB6F5),
    secondarySubtle: Color(0xFF1A1D2E),
    success: Color(0xFF6ED79B),
    warning: Color(0xFFFFC44D),
    danger: Color(0xFFFF8A72),
    info: Color(0xFF7FD4F5),
  );

  /// Fully transparent, used by ghost and text variants.
  static const Color transparent = Color(0x00000000);

  /// The names of every color token, in declaration order.
  static const List<String> tokenNames = <String>[
    'bgCanvas',
    'bgSurface',
    'bgRaised',
    'bgSunken',
    'fgDefault',
    'fgMuted',
    'fgSubtle',
    'borderSubtle',
    'borderDefault',
    'borderStrong',
    'accent',
    'accentHover',
    'accentPressed',
    'accentSubtle',
    'accentBorder',
    'fgOnAccent',
    'secondary',
    'secondarySubtle',
    'success',
    'warning',
    'danger',
    'info',
  ];

  /// Every palette, keyed by the variant name used in `tokens.json`.
  static const Map<String, LimpidColors> byName = <String, LimpidColors>{
    'paper': paper,
    'sepia': sepia,
    'night': night,
    'contrast': contrast,
  };

  /// Alpha applied to the `tertiaryContainer` and `errorContainer` slots of
  /// the generated [ColorScheme].
  static const double _containerAlpha = 0.16;

  /// The page background.
  final Color bgCanvas;

  /// The background of cards, sheets and panels.
  final Color bgSurface;

  /// The background of elements floating above a surface.
  final Color bgRaised;

  /// The background of recessed areas such as wells and code blocks.
  final Color bgSunken;

  /// The default foreground color.
  final Color fgDefault;

  /// The foreground color of secondary text.
  final Color fgMuted;

  /// The foreground color of hints and placeholders.
  final Color fgSubtle;

  /// The hairline border color.
  final Color borderSubtle;

  /// The default border color.
  final Color borderDefault;

  /// The border color of focused or emphasised containers.
  final Color borderStrong;

  /// The primary action color.
  final Color accent;

  /// The primary action color on hover.
  final Color accentHover;

  /// The primary action color when pressed.
  final Color accentPressed;

  /// The tinted background of an accent surface.
  final Color accentSubtle;

  /// The border color of an accent surface.
  final Color accentBorder;

  /// The foreground color used on top of the accent color.
  final Color fgOnAccent;

  /// The secondary action color.
  final Color secondary;

  /// The tinted background of a secondary surface.
  final Color secondarySubtle;

  /// The success status color.
  final Color success;

  /// The warning status color.
  final Color warning;

  /// The danger status color.
  final Color danger;

  /// The informational status color.
  final Color info;

  /// Whether this palette is a dark one.
  bool get isDark =>
      ThemeData.estimateBrightnessForColor(bgCanvas) == Brightness.dark;

  /// The tone used for shadows and elevation overlays.
  ///
  /// Light palettes use the (near black) default foreground, dark palettes use
  /// the (near black) canvas so that shadows never turn light.
  Color get shadowTone => isDark ? bgCanvas : fgDefault;

  /// Returns the value of a token by its name.
  ///
  /// Throws an [ArgumentError] when the token is unknown. This is the entry
  /// point used by the token export tooling and by the parity tests.
  Color valueOf(String token) => switch (token) {
    'bgCanvas' => bgCanvas,
    'bgSurface' => bgSurface,
    'bgRaised' => bgRaised,
    'bgSunken' => bgSunken,
    'fgDefault' => fgDefault,
    'fgMuted' => fgMuted,
    'fgSubtle' => fgSubtle,
    'borderSubtle' => borderSubtle,
    'borderDefault' => borderDefault,
    'borderStrong' => borderStrong,
    'accent' => accent,
    'accentHover' => accentHover,
    'accentPressed' => accentPressed,
    'accentSubtle' => accentSubtle,
    'accentBorder' => accentBorder,
    'fgOnAccent' => fgOnAccent,
    'secondary' => secondary,
    'secondarySubtle' => secondarySubtle,
    'success' => success,
    'warning' => warning,
    'danger' => danger,
    'info' => info,
    _ => throw ArgumentError.value(token, 'token', 'Unknown color token'),
  };

  /// Builds the Flutter [ColorScheme] of this palette.
  ///
  /// Every slot is mapped explicitly from the token table: no Material
  /// default is relied upon.
  ColorScheme toColorScheme() {
    return ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: fgOnAccent,
      primaryContainer: accentSubtle,
      onPrimaryContainer: fgDefault,
      secondary: secondary,
      onSecondary: fgOnAccent,
      secondaryContainer: secondarySubtle,
      onSecondaryContainer: fgDefault,
      tertiary: info,
      onTertiary: fgOnAccent,
      tertiaryContainer: info.withValues(alpha: _containerAlpha),
      onTertiaryContainer: fgDefault,
      error: danger,
      onError: fgOnAccent,
      errorContainer: danger.withValues(alpha: _containerAlpha),
      onErrorContainer: fgDefault,
      surface: bgSurface,
      onSurface: fgDefault,
      onSurfaceVariant: fgMuted,
      surfaceDim: bgSunken,
      surfaceBright: bgRaised,
      surfaceContainerLowest: bgSunken,
      surfaceContainerLow: bgCanvas,
      surfaceContainer: bgCanvas,
      surfaceContainerHigh: bgRaised,
      surfaceContainerHighest: bgRaised,
      outline: borderDefault,
      outlineVariant: borderSubtle,
      inverseSurface: fgDefault,
      onInverseSurface: bgSurface,
      inversePrimary: accentHover,
      surfaceTint: bgSurface,
    );
  }

  @override
  LimpidColors copyWith() => this;

  @override
  LimpidColors lerp(covariant ThemeExtension<LimpidColors>? other, double t) {
    if (other is! LimpidColors) {
      return this;
    }
    return LimpidColors(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgRaised: Color.lerp(bgRaised, other.bgRaised, t)!,
      bgSunken: Color.lerp(bgSunken, other.bgSunken, t)!,
      fgDefault: Color.lerp(fgDefault, other.fgDefault, t)!,
      fgMuted: Color.lerp(fgMuted, other.fgMuted, t)!,
      fgSubtle: Color.lerp(fgSubtle, other.fgSubtle, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      fgOnAccent: Color.lerp(fgOnAccent, other.fgOnAccent, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondarySubtle: Color.lerp(secondarySubtle, other.secondarySubtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
