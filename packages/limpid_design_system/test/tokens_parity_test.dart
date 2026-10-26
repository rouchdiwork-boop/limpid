import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Formats a color the same way the exporter does.
String _hex(Color color) {
  final int value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

void main() {
  late Map<String, dynamic> tokens;

  setUpAll(() {
    final File file = File('tokens.json');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'tokens.json is missing. Generate it with '
          '`flutter test tool/export_tokens.dart`.',
    );
    tokens = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('tokens.json parity', () {
    test('exposes every section', () {
      expect(
        tokens.keys.toSet(),
        containsAll(<String>[
          'colors',
          'typography',
          'spacing',
          'radii',
          'elevation',
          'motion',
        ]),
      );
    });

    test('colors carry the same hexadecimal values as the Dart constants', () {
      final Map<String, dynamic> colors =
          tokens['colors'] as Map<String, dynamic>;

      expect(colors.keys.toSet(), equals(LimpidColors.byName.keys.toSet()));

      for (final MapEntry<String, LimpidColors> entry
          in LimpidColors.byName.entries) {
        final Map<String, dynamic> palette =
            colors[entry.key] as Map<String, dynamic>;
        expect(
          palette.keys.toSet(),
          equals(LimpidColors.tokenNames.toSet()),
          reason: 'the ${entry.key} palette does not expose the same tokens',
        );

        for (final String token in LimpidColors.tokenNames) {
          expect(
            palette[token],
            _hex(entry.value.valueOf(token)),
            reason: '${entry.key}.$token drifted between Dart and JSON',
          );
        }
      }
    });

    test('typography carries the same values as the Dart constants', () {
      final Map<String, dynamic> typography =
          tokens['typography'] as Map<String, dynamic>;

      expect(
        typography.keys.toSet(),
        equals(LimpidTypography.scale.keys.toSet()),
      );

      for (final MapEntry<String, LimpidTypeToken> entry
          in LimpidTypography.scale.entries) {
        final Map<String, dynamic> token =
            typography[entry.key] as Map<String, dynamic>;
        final LimpidTypeToken expected = entry.value;

        expect(token['fontFamily'], expected.family, reason: entry.key);
        expect(token['fontSize'], expected.size, reason: entry.key);
        expect(token['lineHeight'], expected.lineHeight, reason: entry.key);
        expect(token['fontWeight'], expected.weight.value, reason: entry.key);
        expect(
          token['letterSpacing'],
          expected.letterSpacing,
          reason: entry.key,
        );
      }
    });

    test('spacing carries the same values as the Dart constants', () {
      final List<dynamic> spacing = tokens['spacing'] as List<dynamic>;

      expect(spacing.length, LimpidSpacing.values.length);
      for (int index = 0; index < spacing.length; index++) {
        expect(spacing[index], LimpidSpacing.values[index]);
      }
    });

    test('radii carry the same values as the Dart constants', () {
      final Map<String, dynamic> radii =
          tokens['radii'] as Map<String, dynamic>;
      const LimpidRadii expected = LimpidRadii();

      expect(radii['none'], expected.none);
      expect(radii['xs'], expected.xs);
      expect(radii['sm'], expected.sm);
      expect(radii['md'], expected.md);
      expect(radii['lg'], expected.lg);
      expect(radii['xl'], expected.xl);
      expect(radii['xxl'], expected.xxl);
      expect(radii['pill'], expected.pill);
    });

    test('motion carries the same values as the Dart constants', () {
      final Map<String, dynamic> motion =
          tokens['motion'] as Map<String, dynamic>;
      final Map<String, dynamic> durations =
          motion['durations'] as Map<String, dynamic>;
      const LimpidMotion expected = LimpidMotion();

      expect(durations['instant'], expected.instant.inMilliseconds);
      expect(durations['fast'], expected.fast.inMilliseconds);
      expect(durations['base'], expected.base.inMilliseconds);
      expect(durations['slow'], expected.slow.inMilliseconds);
      expect(durations['slower'], expected.slower.inMilliseconds);
    });

    test('elevation exposes the five levels of every variant', () {
      final Map<String, dynamic> elevation =
          tokens['elevation'] as Map<String, dynamic>;

      expect(elevation.keys.toSet(), equals(LimpidColors.byName.keys.toSet()));

      for (final MapEntry<String, dynamic> entry in elevation.entries) {
        final Map<String, dynamic> levels = entry.value as Map<String, dynamic>;
        expect(
          levels.keys.toSet(),
          equals(LimpidElevation.levelNames.toSet()),
          reason: entry.key,
        );
      }
    });
  });
}
