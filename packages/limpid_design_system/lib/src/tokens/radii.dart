import 'package:flutter/foundation.dart';

/// The canonical corner radius scale of the Limpid design system.
///
/// The scale mixes very small radii (inputs, chips) with generous ones
/// (cards, sheets). [pill] is meant for fully rounded elements such as
/// avatars and badges.
@immutable
class LimpidRadii {
  /// Creates the radius scale. All values are expressed in logical pixels.
  const LimpidRadii({
    this.none = 0,
    this.xs = 4,
    this.sm = 6,
    this.md = 10,
    this.lg = 14,
    this.xl = 20,
    this.xxl = 28,
    this.pill = 999,
  });

  /// Square corners.
  final double none;

  /// Extra small radius, used by inputs and small chips.
  final double xs;

  /// Small radius, used by buttons and list tiles.
  final double sm;

  /// Default radius, used by cards and menus.
  final double md;

  /// Large radius, used by dialogs.
  final double lg;

  /// Extra large radius, used by bottom sheets.
  final double xl;

  /// Very large radius, used by hero surfaces.
  final double xxl;

  /// Fully rounded radius, used by pills and avatars.
  final double pill;

  /// Every value of the scale, in ascending order.
  static const List<double> values = <double>[0, 4, 6, 10, 14, 20, 28, 999];

  @override
  String toString() => 'LimpidRadii(${values.join(', ')})';
}
