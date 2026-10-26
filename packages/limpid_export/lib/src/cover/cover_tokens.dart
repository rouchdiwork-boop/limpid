/// The design system tokens the generated covers are drawn from.
///
/// The values mirror the `paper` palette of the Limpid design system
/// (`packages/limpid_design_system/tokens.json`, section `colors.paper`).
/// The export package is pure Dart and cannot depend on the Flutter design
/// system, so the handful of tokens it needs are mirrored here as Dart
/// constants. No colour is ever invented inside the generator.
///
/// The six palettes are the ones the application uses for the covers of the
/// library (`ProjectCover._paletteOf`): a book keeps the same colour in the
/// application and in its exported cover.
class CoverTokens {
  const CoverTokens._();

  /// The file the tokens are read from.
  static const String source = 'packages/limpid_design_system/tokens.json';

  /// The variant of the design system the covers are drawn from.
  static const String paletteName = 'paper';

  /// The accent colour (`accent`).
  static const String accent = '#9C5518';

  /// The secondary colour (`secondary`).
  static const String secondary = '#35407E';

  /// The success colour (`success`).
  static const String success = '#3E6B4F';

  /// The warning colour (`warning`).
  static const String warning = '#8A6410';

  /// The danger colour (`danger`).
  static const String danger = '#A8341F';

  /// The info colour (`info`).
  static const String info = '#2E5F7A';

  /// The page background (`bgCanvas`), used as the ink of the cover.
  static const String ink = '#FAF8F4';

  /// The default foreground (`fgDefault`), used as the shade of the
  /// gradient.
  static const String shade = '#16130F';

  /// The six palettes a book can be drawn from, in the order of the
  /// application.
  static const List<String> palette = <String>[
    accent,
    secondary,
    success,
    warning,
    danger,
    info,
  ];
}
