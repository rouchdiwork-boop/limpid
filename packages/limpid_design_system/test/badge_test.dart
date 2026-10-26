import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'test_helpers.dart';

void main() {
  group('LimpidBadge', () {
    testWidgets('renders its label', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidBadge(label: 'Brouillon')),
      );

      expect(find.text('Brouillon'), findsOneWidget);
    });

    testWidgets('carries an icon so that the color is never alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidBadge(
            label: 'En ligne',
            variant: LimpidStatusVariant.success,
          ),
        ),
      );

      expect(find.text('En ligne'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('uses the color of its variant', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidBadge(
            label: 'Erreur',
            variant: LimpidStatusVariant.danger,
          ),
        ),
      );

      final Text label = tester.widget<Text>(find.text('Erreur'));
      expect(label.style?.color, LimpidColors.paper.danger);
    });

    testWidgets('can display a dot instead of an icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidBadge(label: 'Lu', showDot: true)),
      );

      expect(find.byType(Icon), findsNothing);
    });
  });

  group('LimpidChip', () {
    testWidgets('calls onTap when tapped', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        wrapWithLimpid(LimpidChip(label: 'Polar', onTap: () => taps++)),
      );

      await tester.tap(find.byType(LimpidChip));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('calls onDeleted when removed', (WidgetTester tester) async {
      int deletes = 0;
      await tester.pumpWidget(
        wrapWithLimpid(LimpidChip(label: 'Polar', onDeleted: () => deletes++)),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(deletes, 1);
    });
  });

  group('LimpidTag', () {
    testWidgets('renders its label', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidTag(label: 'Manuscrit')),
      );

      expect(find.text('Manuscrit'), findsOneWidget);
    });
  });
}
