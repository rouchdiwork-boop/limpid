import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

void main() {
  group('LimpidTheme', () {
    test('builds the four themes of the design system', () {
      expect(LimpidThemeVariant.values, <LimpidThemeVariant>[
        LimpidThemeVariant.paper,
        LimpidThemeVariant.sepia,
        LimpidThemeVariant.night,
        LimpidThemeVariant.contrast,
      ]);
    });

    test('each theme uses the canvas of its palette', () {
      final Map<LimpidThemeVariant, Color> expected =
          <LimpidThemeVariant, Color>{
            LimpidThemeVariant.paper: const Color(0xFFFAF8F4),
            LimpidThemeVariant.sepia: const Color(0xFFF4EBD8),
            LimpidThemeVariant.night: const Color(0xFF14110E),
            LimpidThemeVariant.contrast: const Color(0xFF000000),
          };

      for (final MapEntry<LimpidThemeVariant, Color> entry
          in expected.entries) {
        final ThemeData theme = LimpidTheme.of(entry.key);
        expect(
          theme.scaffoldBackgroundColor,
          entry.value,
          reason: entry.key.name,
        );
        expect(theme.colorScheme.primary, entry.key.colors.accent);
      }
    });

    test('the night and contrast themes are dark', () {
      expect(
        LimpidTheme.of(LimpidThemeVariant.night).brightness,
        Brightness.dark,
      );
      expect(
        LimpidTheme.of(LimpidThemeVariant.contrast).brightness,
        Brightness.dark,
      );
      expect(
        LimpidTheme.of(LimpidThemeVariant.paper).brightness,
        Brightness.light,
      );
    });

    test('registers the token scopes', () {
      final ThemeData theme = LimpidTheme.of(LimpidThemeVariant.sepia);

      expect(theme.extension<LimpidColors>(), isNotNull);
      expect(theme.extension<LimpidElevation>(), isNotNull);
      expect(theme.extension<LimpidThemeScope>(), isNotNull);
    });

    test('builds the text theme from the type scale', () {
      final ThemeData theme = LimpidTheme.of(LimpidThemeVariant.paper);

      expect(theme.textTheme.displayLarge?.fontSize, 40);
      expect(theme.textTheme.displayLarge?.fontFamily, 'Fraunces');
      expect(theme.textTheme.bodyMedium?.fontSize, 14);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Instrument Sans');
      expect(theme.textTheme.labelSmall?.letterSpacing, 0.44);
    });

    testWidgets('context.limpid exposes the tokens of the active theme', (
      WidgetTester tester,
    ) async {
      late LimpidThemeScope scope;
      await tester.pumpWidget(
        MaterialApp(
          theme: LimpidTheme.of(LimpidThemeVariant.night),
          home: Builder(
            builder: (BuildContext context) {
              scope = context.limpid;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(scope.variant, LimpidThemeVariant.night);
      expect(scope.colors.bgCanvas, const Color(0xFF14110E));
      expect(scope.spacing.space16, 16);
      expect(scope.radii.md, 10);
      expect(scope.motion.base, const Duration(milliseconds: 180));
    });

    test('the motion curves follow the CSS cubic bezier specification', () {
      const LimpidCubicBezier curve = LimpidCubicBezier(0.2, 0, 0, 1);

      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      expect(curve.transform(0.5), closeTo(0.878, 0.01));
    });
  });
}
