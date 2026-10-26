// Generates `tokens.json` from the Dart constants of the design system.
//
// The JSON export feeds the HTML mockups and the Figma library. It is
// generated — never hand edited — so that the Dart code stays the single
// source of truth.
//
// The package depends on Flutter, so the generator is executed by the
// Flutter test runner (which is the only environment providing `dart:ui`):
//
//     flutter test tool/export_tokens.dart
//
// The command reports one passing test and rewrites `tokens.json`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Builds the JSON representation of a color.
String _hex(Color color) {
  final int value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Builds the JSON representation of a shadow.
Map<String, Object> _shadow(BoxShadow shadow) => <String, Object>{
  'color': _hex(shadow.color),
  'offsetX': shadow.offset.dx,
  'offsetY': shadow.offset.dy,
  'blurRadius': shadow.blurRadius,
  'spreadRadius': shadow.spreadRadius,
};

/// Builds the JSON representation of an elevation scale.
Map<String, Object> _elevation(LimpidElevation elevation) {
  final Map<String, Object> result = <String, Object>{};
  for (final String name in LimpidElevation.levelNames) {
    result[name] = elevation.byName(name).map(_shadow).toList(growable: false);
  }
  return result;
}

/// Builds the JSON representation of the color palettes.
Map<String, Object> _colors() {
  final Map<String, Object> result = <String, Object>{};
  for (final MapEntry<String, LimpidColors> entry
      in LimpidColors.byName.entries) {
    final Map<String, String> palette = <String, String>{};
    for (final String token in LimpidColors.tokenNames) {
      palette[token] = _hex(entry.value.valueOf(token));
    }
    result[entry.key] = palette;
  }
  return result;
}

/// Builds the JSON representation of the type scale.
Map<String, Object> _typography() {
  final Map<String, Object> result = <String, Object>{};
  for (final MapEntry<String, LimpidTypeToken> entry
      in LimpidTypography.scale.entries) {
    final LimpidTypeToken token = entry.value;
    result[entry.key] = <String, Object>{
      'fontFamily': token.family,
      'fontSize': token.size,
      'lineHeight': token.lineHeight,
      'fontWeight': token.weight.value,
      'letterSpacing': token.letterSpacing,
    };
  }
  return result;
}

/// Builds the JSON representation of the radius scale.
Map<String, Object> _radii() {
  const LimpidRadii radii = LimpidRadii();
  return <String, Object>{
    'none': radii.none,
    'xs': radii.xs,
    'sm': radii.sm,
    'md': radii.md,
    'lg': radii.lg,
    'xl': radii.xl,
    'xxl': radii.xxl,
    'pill': radii.pill,
  };
}

/// Builds the JSON representation of the motion scale.
Map<String, Object> _motion() {
  const LimpidMotion motion = LimpidMotion();
  return <String, Object>{
    'durations': <String, Object>{
      'instant': motion.instant.inMilliseconds,
      'fast': motion.fast.inMilliseconds,
      'base': motion.base.inMilliseconds,
      'slow': motion.slow.inMilliseconds,
      'slower': motion.slower.inMilliseconds,
    },
    'curves': <String, Object>{
      'standard': <double>[0.2, 0, 0, 1],
      'decelerate': <double>[0, 0, 0, 1],
      'exit': <double>[0.4, 0, 1, 1],
      'emphasized': <double>[0.2, 0, 0, 1],
    },
  };
}

/// Builds the whole token document.
Map<String, Object> buildTokens() {
  return <String, Object>{
    'colors': _colors(),
    'typography': _typography(),
    'spacing': List<double>.of(LimpidSpacing.values),
    'radii': _radii(),
    'elevation': <String, Object>{
      'paper': _elevation(LimpidElevation.light),
      'sepia': _elevation(LimpidElevation.light),
      'night': _elevation(LimpidElevation.dark),
      'contrast': _elevation(LimpidElevation.light),
    },
    'motion': _motion(),
  };
}

/// Returns the absolute path of the package root.
///
/// The Flutter test runner executes the script with the package root as the
/// working directory, which is the only reliable anchor available here.
String _packageRoot() {
  final String current = Directory.current.path;
  final String marker = '$current${Platform.pathSeparator}pubspec.yaml';
  if (!File(marker).existsSync()) {
    throw StateError(
      'pubspec.yaml not found in $current: run the exporter from the package '
      'root.',
    );
  }
  return current;
}

void main() {
  test('exports tokens.json from the Dart constants', () {
    final String target =
        '${_packageRoot()}${Platform.pathSeparator}tokens.json';
    final String json = const JsonEncoder.withIndent(
      '  ',
    ).convert(buildTokens());
    File(target).writeAsStringSync('$json\n');
    stdout.writeln('tokens.json written to $target');
  });
}
