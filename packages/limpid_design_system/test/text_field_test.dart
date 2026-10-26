import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'test_helpers.dart';

void main() {
  group('LimpidTextField', () {
    testWidgets('renders its label and its hint', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidTextField(label: 'Titre', hint: 'Le titre du livre'),
        ),
      );

      expect(find.text('Titre'), findsOneWidget);
      expect(find.text('Le titre du livre'), findsOneWidget);
    });

    testWidgets('reports every change', (WidgetTester tester) async {
      final List<String> changes = <String>[];
      await tester.pumpWidget(
        wrapWithLimpid(LimpidTextField(label: 'Titre', onChanged: changes.add)),
      );

      await tester.enterText(find.byType(TextField), 'Limpid');
      await tester.pump();

      expect(changes, <String>['Limpid']);
    });

    testWidgets('displays its error text', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidTextField(label: 'Titre', errorText: 'Ce titre existe'),
        ),
      );

      expect(find.text('Ce titre existe'), findsOneWidget);
    });

    testWidgets('is read only when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidTextField(label: 'Titre', enabled: false)),
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    testWidgets('exposes the label to screen readers', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapWithLimpid(const LimpidTextField(label: 'Titre')),
      );

      final SemanticsNode node = tester.getSemantics(
        find.byType(LimpidTextField),
      );
      expect(node.label, 'Titre');
      expect(node.flagsCollection.isTextField, isTrue);

      handle.dispose();
    });
  });

  group('LimpidTextArea', () {
    testWidgets('renders a multi line field', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          const LimpidTextArea(label: 'Notes', minLines: 2, maxLines: 6),
        ),
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 2);
      expect(field.maxLines, 6);
    });
  });

  group('LimpidSearchField', () {
    testWidgets('clears its value', (WidgetTester tester) async {
      int clears = 0;
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidSearchField(hint: 'Rechercher', onCleared: () => clears++),
        ),
      );

      await tester.enterText(find.byType(TextField), 'scène');
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(clears, 1);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  group('LimpidSelect', () {
    testWidgets('shows the selected value', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithLimpid(
          LimpidSelect<String>(
            label: 'Statut',
            items: const <LimpidSelectItem<String>>[
              LimpidSelectItem<String>(value: 'draft', label: 'Brouillon'),
              LimpidSelectItem<String>(value: 'done', label: 'Terminé'),
            ],
            value: 'draft',
            onChanged: (String? _) {},
          ),
        ),
      );

      expect(find.text('Brouillon'), findsOneWidget);
    });
  });
}
