import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/elevation.dart';

/// The four themes shipped by the Limpid design system.
///
/// The variant is a global, user owned choice: it is stored in the user
/// settings and synchronised between devices (see D-14).
enum LimpidThemeVariant {
  /// The default working theme: a warm, near-white paper.
  paper,

  /// A warm sepia theme meant for long reading sessions.
  sepia,

  /// The dark theme used for night writing.
  night,

  /// The high contrast theme, compliant with WCAG AAA.
  contrast,
}

/// The design system tokens attached to a [LimpidThemeVariant].
extension LimpidThemeVariantTokens on LimpidThemeVariant {
  /// Whether the variant is a dark one.
  bool get isDark => switch (this) {
    LimpidThemeVariant.paper || LimpidThemeVariant.sepia => false,
    LimpidThemeVariant.night || LimpidThemeVariant.contrast => true,
  };

  /// The color palette of the variant.
  LimpidColors get colors => switch (this) {
    LimpidThemeVariant.paper => LimpidColors.paper,
    LimpidThemeVariant.sepia => LimpidColors.sepia,
    LimpidThemeVariant.night => LimpidColors.night,
    LimpidThemeVariant.contrast => LimpidColors.contrast,
  };

  /// The elevation scale of the variant.
  LimpidElevation get elevation =>
      isDark ? LimpidElevation.dark : LimpidElevation.light;

  /// The name of the variant, as used in `tokens.json`.
  String get tokenName => name;
}
