import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'test_helpers.dart';

void main() {
  group('LimpidButton', () {
    testWidgets('keeps its label in sentence case', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Enregistrer')),
      );

      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidButton(label: 'Enregistrer', onPressed: () => presses++),
        ),
      );

      await tester.tap(find.byType(LimpidButton));
      await tester.pump();

      expect(presses, 1);
    });

    testWidgets('is disabled when onPressed is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Enregistrer')),
      );

      final ElevatedButton button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows a busy indicator and ignores presses while loading', (
      WidgetTester tester,
    ) async {
      int presses = 0;
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidButton(
            label: 'Enregistrer',
            loading: true,
            onPressed: () => presses++,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);

      await tester.tap(find.byType(LimpidButton));
      await tester.pump();

      expect(presses, 0);
    });

    testWidgets('primary variant is filled with the accent color', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Enregistrer')),
      );

      final ElevatedButton button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      final Color? background = button.style?.backgroundColor?.resolve(
        <WidgetState>{},
      );

      expect(background, LimpidColors.paper.accent);
    });

    testWidgets('danger variant is filled with the danger color', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidButton(
            label: 'Supprimer',
            variant: LimpidButtonVariant.danger,
          ),
        ),
      );

      final ElevatedButton button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      final Color? background = button.style?.backgroundColor?.resolve(
        <WidgetState>{},
      );

      expect(background, LimpidColors.paper.danger);
    });

    testWidgets('ghost and text variants are transparent', (
      WidgetTester tester,
    ) async {
      for (final LimpidButtonVariant variant in <LimpidButtonVariant>[
        LimpidButtonVariant.ghost,
        LimpidButtonVariant.text,
      ]) {
        await tester.pumpWidget(
          wrapWithLimpid(LimpidButton(label: 'Annuler', variant: variant)),
        );

        final TextButton button = tester.widget<TextButton>(
          find.byType(TextButton),
        );
        final Color? background = button.style?.backgroundColor?.resolve(
          <WidgetState>{},
        );

        expect(background, LimpidColors.transparent);
      }
    });

    testWidgets('renders an icon when one is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Ajouter', icon: Icons.add)),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('keeps a padded tap target in every theme', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Enregistrer')),
      );

      final BuildContext context = tester.element(find.byType(LimpidButton));
      expect(
        Theme.of(context).materialTapTargetSize,
        MaterialTapTargetSize.padded,
      );
    });

    testWidgets('is announced as a button by screen readers', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidButton(label: 'Enregistrer')),
      );

      final SemanticsNode node = tester.getSemantics(find.byType(LimpidButton));
      expect(node.label, 'Enregistrer');
      expect(node.flagsCollection.isButton, isTrue);

      handle.dispose();
    });
  });

  group('LimpidIconButton', () {
    testWidgets('renders its icon and its tooltip', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidIconButton(icon: Icons.delete, tooltip: 'Supprimer'),
        ),
      );

      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('keeps a 44 pixel hit target', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidIconButton(icon: Icons.delete, tooltip: 'Supprimer'),
        ),
      );

      final Size size = tester.getSize(find.byType(LimpidIconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
