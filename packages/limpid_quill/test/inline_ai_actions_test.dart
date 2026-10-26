import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import 'test_helpers.dart';

void main() {
  group('Différentiel des suggestions', () {
    test('il sépare les ajouts et les suppressions', () {
      final List<LimpidDiffSegment> segments = diffWords(
        'le chat noir',
        'le chat blanc',
      );

      expect(segments, hasLength(3));
      expect(segments[0].kind, LimpidDiffKind.unchanged);
      expect(segments[1].kind, LimpidDiffKind.deletion);
      expect(segments[1].text, 'noir');
      expect(segments[2].kind, LimpidDiffKind.insertion);
      expect(segments[2].text, 'blanc');
    });

    test('il restitue le texte de la suggestion', () {
      final String original = 'Une phrase simple, sans éclat.';
      final String suggestion = 'Une phrase vive, pleine d’éclat.';

      final String rebuilt = diffWords(original, suggestion)
          .where(
            (LimpidDiffSegment segment) =>
                segment.kind != LimpidDiffKind.deletion,
          )
          .map((LimpidDiffSegment segment) => segment.text)
          .join();

      expect(rebuilt, suggestion);
    });
  });

  group('Barre d’actions IA', () {
    testWidgets('elle propose les six actions', (tester) async {
      final List<LimpidAiAction> chosen = <LimpidAiAction>[];

      await tester.pumpWidget(
        limpidTestApp(child: LimpidInlineAiActions(onAction: chosen.add)),
      );
      await tester.pump();

      expect(find.text('Réécrire'), findsOneWidget);
      expect(find.text('Étendre'), findsOneWidget);
      expect(find.text('Raccourcir'), findsOneWidget);
      expect(find.text('Simplifier'), findsOneWidget);
      expect(find.text('Changer le ton'), findsOneWidget);
      expect(find.text('Traduire'), findsOneWidget);

      await tester.tap(find.text('Réécrire'));
      await tester.pump();

      expect(chosen, <LimpidAiAction>[LimpidAiAction.rewrite]);
    });

    testWidgets('elle présente la suggestion en différentiel', (tester) async {
      final LimpidAiSuggestion suggestion = LimpidAiSuggestion(
        original: 'le chat noir',
        suggestion: 'le chat blanc',
      );

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidInlineAiActions(
            onAction: (LimpidAiAction action) {},
            suggestion: suggestion,
          ),
        ),
      );
      await tester.pump();

      final RichText rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere(
            (RichText text) => text.text.toPlainText().contains('noir'),
          );
      final TextSpan root = rich.text as TextSpan;
      // `Text.rich` wraps the span it receives in a parent span.
      final TextSpan diff = root.children?.length == 1
          ? root.children!.first as TextSpan
          : root;
      final List<InlineSpan> spans = diff.children!;

      expect(spans, hasLength(3));
      final TextSpan removed = spans[1] as TextSpan;
      final TextSpan added = spans[2] as TextSpan;
      expect(removed.text, 'noir');
      expect(removed.style?.decoration, TextDecoration.lineThrough);
      expect(removed.style?.color, LimpidColors.paper.danger);
      expect(added.text, 'blanc');
      expect(added.style?.decoration, TextDecoration.underline);
      expect(added.style?.color, LimpidColors.paper.success);
    });

    testWidgets('elle offre appliquer, ignorer et régénérer', (tester) async {
      bool applied = false;
      bool dismissed = false;
      bool regenerated = false;

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidInlineAiActions(
            onAction: (LimpidAiAction action) {},
            suggestion: LimpidAiSuggestion(
              original: 'le chat noir',
              suggestion: 'le chat blanc',
            ),
            onApply: () => applied = true,
            onDismiss: () => dismissed = true,
            onRegenerate: () => regenerated = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Appliquer'), findsOneWidget);
      expect(find.text('Ignorer'), findsOneWidget);
      expect(find.text('Régénérer'), findsOneWidget);

      await tester.tap(find.text('Appliquer'));
      await tester.tap(find.text('Ignorer'));
      await tester.tap(find.text('Régénérer'));
      await tester.pump();

      expect(applied, isTrue);
      expect(dismissed, isTrue);
      expect(regenerated, isTrue);
    });
  });

  group('Ancres de commentaire', () {
    test('le texte ancré est souligné en pointillé', () {
      const List<LimpidCommentAnchor> anchors = <LimpidCommentAnchor>[
        LimpidCommentAnchor(
          id: 'c1',
          range: MarkRange(start: 3, end: 8),
          body: 'Note de relecture',
        ),
      ];

      final TextStyle? style = commentAnchorStyle(
        style: const TextStyle(),
        offset: 5,
        anchors: anchors,
        hoveredAnchorId: null,
        colors: LimpidColors.paper,
      );

      expect(style, isNotNull);
      expect(style!.decoration, TextDecoration.underline);
      expect(style.decorationStyle, TextDecorationStyle.dotted);
      expect(style.decorationColor, LimpidColors.paper.secondary);
      expect(style.backgroundColor, isNull);
    });

    test('le survol pose le fond secondaire', () {
      const List<LimpidCommentAnchor> anchors = <LimpidCommentAnchor>[
        LimpidCommentAnchor(
          id: 'c1',
          range: MarkRange(start: 3, end: 8),
          body: 'Note de relecture',
        ),
      ];

      final TextStyle? style = commentAnchorStyle(
        style: const TextStyle(),
        offset: 5,
        anchors: anchors,
        hoveredAnchorId: 'c1',
        colors: LimpidColors.paper,
      );

      expect(style!.backgroundColor, LimpidColors.paper.secondarySubtle);
    });

    test('un offset hors de la plage n’est pas ancré', () {
      const List<LimpidCommentAnchor> anchors = <LimpidCommentAnchor>[
        LimpidCommentAnchor(
          id: 'c1',
          range: MarkRange(start: 3, end: 8),
          body: 'Note de relecture',
        ),
      ];

      final TextStyle? style = commentAnchorStyle(
        style: const TextStyle(),
        offset: 12,
        anchors: anchors,
        hoveredAnchorId: null,
        colors: LimpidColors.paper,
      );

      expect(style, isNull);
    });

    testWidgets('la liste des commentaires sélectionne la plage', (
      tester,
    ) async {
      LimpidCommentAnchor? selected;
      const List<LimpidCommentAnchor> anchors = <LimpidCommentAnchor>[
        LimpidCommentAnchor(
          id: 'c1',
          range: MarkRange(start: 0, end: 4),
          body: 'Attention à la chronologie',
        ),
      ];

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidCommentAnchors(
            anchors: anchors,
            onSelect: (LimpidCommentAnchor anchor) => selected = anchor,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Attention à la chronologie'), findsOneWidget);

      await tester.tap(find.text('Attention à la chronologie'));
      await tester.pump();

      expect(selected?.id, 'c1');
      expect(selected?.range, const MarkRange(start: 0, end: 4));
    });
  });
}
