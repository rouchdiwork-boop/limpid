import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'test_helpers.dart';

void main() {
  group('LimpidBanner', () {
    testWidgets('renders its title and its message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidBanner(
            variant: LimpidStatusVariant.warning,
            title: 'Connexion perdue',
            message: 'Les modifications sont enregistrées localement.',
          ),
        ),
      );

      expect(find.text('Connexion perdue'), findsOneWidget);
      expect(
        find.text('Les modifications sont enregistrées localement.'),
        findsOneWidget,
      );
    });

    testWidgets('carries an icon so that the color is never alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidBanner(
            variant: LimpidStatusVariant.danger,
            title: 'Échec de la sauvegarde',
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
      expect(find.byIcon(LimpidIcons.danger), findsOneWidget);
    });

    testWidgets('uses the color of its variant', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidBanner(
            variant: LimpidStatusVariant.success,
            title: 'Sauvegardé',
          ),
        ),
      );

      final Icon icon = tester.widget<Icon>(find.byIcon(LimpidIcons.success));
      expect(icon.color, LimpidColors.paper.success);
    });

    testWidgets('displays its action', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidBanner(
            variant: LimpidStatusVariant.info,
            title: 'Nouvelle version',
            action: LimpidButton(
              label: 'Actualiser',
              variant: LimpidButtonVariant.text,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Actualiser'), findsOneWidget);
    });

    testWidgets('calls onDismiss when dismissed', (WidgetTester tester) async {
      int dismissals = 0;
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidBanner(
            variant: LimpidStatusVariant.info,
            title: 'Information',
            onDismiss: () => dismissals++,
          ),
        ),
      );

      await tester.tap(find.byIcon(LimpidIcons.close));
      await tester.pump();

      expect(dismissals, 1);
    });
  });
}
