import 'package:flutter/material.dart';

/// The five elevation levels of the Limpid design system.
///
/// Light palettes use soft, warm shadows; dark palettes use pure black
/// shadows and rely on a hairline border to separate the raised surface from
/// the canvas (see [usesHairlineBorder]).
@immutable
class LimpidElevation extends ThemeExtension<LimpidElevation> {
  /// Creates an elevation scale.
  const LimpidElevation({
    required this.level0,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.level4,
    this.usesHairlineBorder = false,
  });

  /// The elevation scale used by the light palettes.
  static const LimpidElevation light = LimpidElevation(
    level0: <BoxShadow>[],
    level1: <BoxShadow>[
      BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 2),
    ],
    level2: <BoxShadow>[
      BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 6),
    ],
    level3: <BoxShadow>[
      BoxShadow(color: Color(0x1F000000), offset: Offset(0, 4), blurRadius: 12),
    ],
    level4: <BoxShadow>[
      BoxShadow(color: Color(0x24000000), offset: Offset(0, 8), blurRadius: 24),
    ],
  );

  /// The elevation scale used by the dark palettes.
  static const LimpidElevation dark = LimpidElevation(
    level0: <BoxShadow>[],
    level1: <BoxShadow>[
      BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
    ],
    level2: <BoxShadow>[
      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
    ],
    level3: <BoxShadow>[
      BoxShadow(color: Color(0x59000000), offset: Offset(0, 4), blurRadius: 12),
    ],
    level4: <BoxShadow>[
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 8), blurRadius: 24),
    ],
  );

  /// No shadow at all.
  final List<BoxShadow> level0;

  /// The shadow of a resting surface.
  final List<BoxShadow> level1;

  /// The shadow of a raised surface.
  final List<BoxShadow> level2;

  /// The shadow of a floating surface.
  final List<BoxShadow> level3;

  /// The shadow of a modal surface.
  final List<BoxShadow> level4;

  /// Whether raised surfaces must be separated by a hairline border.
  ///
  /// True for the dark palettes, where a shadow alone is not readable.
  final bool usesHairlineBorder;

  /// The names of the elevation levels, from the lowest to the highest.
  static const List<String> levelNames = <String>['e0', 'e1', 'e2', 'e3', 'e4'];

  /// Returns the shadows of the level named [name] (e.g. `e2`).
  List<BoxShadow> byName(String name) => switch (name) {
    'e0' => level0,
    'e1' => level1,
    'e2' => level2,
    'e3' => level3,
    'e4' => level4,
    _ => throw ArgumentError.value(name, 'name', 'Unknown elevation level'),
  };

  @override
  LimpidElevation copyWith() => this;

  @override
  LimpidElevation lerp(
    covariant ThemeExtension<LimpidElevation>? other,
    double t,
  ) {
    if (other is! LimpidElevation) {
      return this;
    }
    return LimpidElevation(
      level0: level0,
      level1: BoxShadow.lerpList(level1, other.level1, t)!,
      level2: BoxShadow.lerpList(level2, other.level2, t)!,
      level3: BoxShadow.lerpList(level3, other.level3, t)!,
      level4: BoxShadow.lerpList(level4, other.level4, t)!,
      usesHairlineBorder: t < 0.5
          ? usesHairlineBorder
          : other.usesHairlineBorder,
    );
  }
}
