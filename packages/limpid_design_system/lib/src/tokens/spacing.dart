import 'package:flutter/foundation.dart';

/// The canonical 4pt spacing scale of the Limpid design system.
///
/// Every value of the scale is available as a named constant so that no
/// screen ever has to inline a padding or a gap. The scale is intentionally
/// small: fourteen steps cover every layout in the product.
///
/// ```dart
/// Padding.all(context.limpid.spacing.space16)
/// ```
@immutable
class LimpidSpacing {
  /// Creates the spacing scale. All values are expressed in logical pixels.
  const LimpidSpacing({
    this.space0 = 0,
    this.space2 = 2,
    this.space4 = 4,
    this.space6 = 6,
    this.space8 = 8,
    this.space12 = 12,
    this.space16 = 16,
    this.space20 = 20,
    this.space24 = 24,
    this.space32 = 32,
    this.space40 = 40,
    this.space48 = 48,
    this.space64 = 64,
    this.space80 = 80,
    this.space96 = 96,
    this.space128 = 128,
  });

  /// No space at all.
  final double space0;

  /// Hairline spacing, used for icon-to-label gaps.
  final double space2;

  /// Tight spacing, used inside dense controls.
  final double space4;

  /// Small spacing, used between related labels.
  final double space6;

  /// Default inline spacing.
  final double space8;

  /// Spacing between a control and its helper text.
  final double space12;

  /// Default block spacing.
  final double space16;

  /// Spacing between the elements of a group.
  final double space20;

  /// Spacing between sibling cards.
  final double space24;

  /// Spacing between sections of a screen.
  final double space32;

  /// Spacing between major blocks.
  final double space40;

  /// Spacing between top level sections.
  final double space48;

  /// Spacing around a full page region.
  final double space64;

  /// Spacing around an empty or loading region.
  final double space80;

  /// Spacing around a hero region.
  final double space96;

  /// Maximum spacing, used for editorial breathing room.
  final double space128;

  /// Every value of the scale, in ascending order.
  static const List<double> values = <double>[
    0,
    2,
    4,
    6,
    8,
    12,
    16,
    20,
    24,
    32,
    40,
    48,
    64,
    80,
    96,
    128,
  ];

  @override
  String toString() => 'LimpidSpacing(${values.join(', ')})';
}
