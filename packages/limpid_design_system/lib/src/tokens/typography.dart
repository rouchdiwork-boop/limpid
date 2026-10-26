import 'package:flutter/material.dart';

/// The four font families of the Limpid design system.
///
/// The faces themselves are embedded as assets by the host application (see
/// D-13): `google_fonts` is forbidden because it downloads at runtime and
/// breaks the offline guarantee of the product. The design system only
/// declares the family names so that both the application and the HTML
/// mockups agree on the typography.
abstract final class LimpidFontFamily {
  /// Editorial serif used for display type and titles.
  static const String display = 'Fraunces';

  /// Grotesque used for the interface.
  static const String interface = 'Instrument Sans';

  /// Serif used for the manuscript (editor and reader).
  static const String manuscript = 'Literata';

  /// Monospace used for data, metadata and counters.
  static const String mono = 'IBM Plex Mono';
}

/// A single entry of the Limpid type scale.
///
/// The token carries the absolute values (size and line height) so that the
/// JSON export and the Flutter styles cannot drift apart.
@immutable
class LimpidTypeToken {
  /// Creates a type scale entry.
  const LimpidTypeToken({
    required this.name,
    required this.family,
    required this.size,
    required this.lineHeight,
    required this.weight,
    required this.letterSpacing,
  });

  /// The token name, e.g. `displayXl`.
  final String name;

  /// The font family of the token.
  final String family;

  /// The font size, in logical pixels.
  final double size;

  /// The line height, in logical pixels.
  final double lineHeight;

  /// The font weight.
  final FontWeight weight;

  /// The letter spacing, in logical pixels.
  final double letterSpacing;

  /// The ratio between the line height and the font size.
  double get lineHeightRatio => lineHeight / size;

  /// Builds the Flutter [TextStyle] of this token.
  TextStyle toStyle({Color? color}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeightRatio,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
  );

  @override
  String toString() => 'LimpidTypeToken($name)';
}

/// The text transformations applied by the design system.
///
/// Flutter has no style level text transformation, so the uppercase label
/// convention of the type scale is applied explicitly by the components
/// through [label].
abstract final class LimpidTextTransform {
  /// Uppercases a label, as required by the label style of the scale.
  ///
  /// ```dart
  /// Text(LimpidTextTransform.label('Enregistrer'))
  /// ```
  static String label(String value) => value.toUpperCase();
}

/// The canonical type scale and the [TextTheme] built from it.
abstract final class LimpidTypography {
  /// The type scale, keyed by token name.
  static const Map<String, LimpidTypeToken> scale = <String, LimpidTypeToken>{
    'displayXl': LimpidTypeToken(
      name: 'displayXl',
      family: LimpidFontFamily.display,
      size: 40,
      lineHeight: 42,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'displayL': LimpidTypeToken(
      name: 'displayL',
      family: LimpidFontFamily.display,
      size: 32,
      lineHeight: 38,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'displayM': LimpidTypeToken(
      name: 'displayM',
      family: LimpidFontFamily.display,
      size: 26,
      lineHeight: 32,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'titleL': LimpidTypeToken(
      name: 'titleL',
      family: LimpidFontFamily.display,
      size: 22,
      lineHeight: 28,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'titleM': LimpidTypeToken(
      name: 'titleM',
      family: LimpidFontFamily.display,
      size: 18,
      lineHeight: 24,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'titleS': LimpidTypeToken(
      name: 'titleS',
      family: LimpidFontFamily.interface,
      size: 15,
      lineHeight: 21,
      weight: FontWeight.w600,
      letterSpacing: 0,
    ),
    'bodyL': LimpidTypeToken(
      name: 'bodyL',
      family: LimpidFontFamily.interface,
      size: 16,
      lineHeight: 26,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
    'bodyM': LimpidTypeToken(
      name: 'bodyM',
      family: LimpidFontFamily.interface,
      size: 14,
      lineHeight: 22,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
    'bodyS': LimpidTypeToken(
      name: 'bodyS',
      family: LimpidFontFamily.interface,
      size: 13,
      lineHeight: 20,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
    'label': LimpidTypeToken(
      name: 'label',
      family: LimpidFontFamily.interface,
      size: 12,
      lineHeight: 16,
      weight: FontWeight.w500,
      letterSpacing: 0.72,
    ),
    'caption': LimpidTypeToken(
      name: 'caption',
      family: LimpidFontFamily.interface,
      size: 11,
      lineHeight: 15,
      weight: FontWeight.w500,
      letterSpacing: 0.44,
    ),
    'mono': LimpidTypeToken(
      name: 'mono',
      family: LimpidFontFamily.mono,
      size: 13,
      lineHeight: 20,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
    'manuscript': LimpidTypeToken(
      name: 'manuscript',
      family: LimpidFontFamily.manuscript,
      size: 18,
      lineHeight: 32,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
    'manuscriptSm': LimpidTypeToken(
      name: 'manuscriptSm',
      family: LimpidFontFamily.manuscript,
      size: 16,
      lineHeight: 28,
      weight: FontWeight.w400,
      letterSpacing: 0,
    ),
  };

  /// Returns the token named [name].
  ///
  /// Throws an [ArgumentError] when the token does not exist.
  static LimpidTypeToken token(String name) {
    final LimpidTypeToken? found = scale[name];
    if (found == null) {
      throw ArgumentError.value(name, 'name', 'Unknown type token');
    }
    return found;
  }

  /// The style of a label, the small uppercase text of the interface.
  static TextStyle labelStyle({Color? color}) =>
      token('label').toStyle(color: color);

  /// The style of a caption, the smallest text of the interface.
  static TextStyle captionStyle({Color? color}) =>
      token('caption').toStyle(color: color);

  /// The style of the manuscript body text.
  static TextStyle manuscriptStyle({Color? color}) =>
      token('manuscript').toStyle(color: color);

  /// The style of the compact manuscript body text.
  static TextStyle manuscriptSmallStyle({Color? color}) =>
      token('manuscriptSm').toStyle(color: color);

  /// The style of monospaced data.
  static TextStyle monoStyle({Color? color}) =>
      token('mono').toStyle(color: color);

  /// Builds the [TextTheme] of the design system.
  ///
  /// The theme is assembled by hand from the type scale — the Material
  /// defaults are never used — so that every slot maps to a canonical token.
  static TextTheme buildTextTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: token('displayXl').toStyle(color: primary),
      displayMedium: token('displayL').toStyle(color: primary),
      displaySmall: token('displayM').toStyle(color: primary),
      headlineLarge: token('titleL').toStyle(color: primary),
      headlineMedium: token('titleM').toStyle(color: primary),
      headlineSmall: token('titleS').toStyle(color: primary),
      titleLarge: token('titleL').toStyle(color: primary),
      titleMedium: token('titleM').toStyle(color: primary),
      titleSmall: token('titleS').toStyle(color: primary),
      bodyLarge: token('bodyL').toStyle(color: primary),
      bodyMedium: token('bodyM').toStyle(color: primary),
      bodySmall: token('bodyS').toStyle(color: primary),
      labelLarge: token('label').toStyle(color: secondary),
      labelMedium: token('label').toStyle(color: secondary),
      labelSmall: token('caption').toStyle(color: secondary),
    );
  }
}
