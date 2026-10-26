import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/revision/history/history_screen.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

const String kHistoryDocumentId = 'document-1';
const DocumentId _documentId = DocumentId(kHistoryDocumentId);
const AuthorId _author = AuthorId('auteur-1');

/// A manuscript of three revisions: a paragraph, then its correction, then a
/// second paragraph.
CrdtDocument fakeHistoryDocument() {
  return CrdtDocument.empty(_documentId)
      .apply(
        const InsertBlockOp(
          doc: _documentId,
          lamport: 1,
          author: _author,
          blockId: BlockId('bloc-1'),
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: TextContent('Le premier.'),
        ),
      )
      .apply(
        const UpdateContentOp(
          doc: _documentId,
          lamport: 2,
          author: _author,
          blockId: BlockId('bloc-1'),
          content: TextContent('Le premier mot.'),
        ),
      )
      .apply(
        InsertBlockOp(
          doc: _documentId,
          lamport: 3,
          author: _author,
          blockId: const BlockId('bloc-2'),
          parent: null,
          order: OrderKey('7'),
          type: BlockType.paragraph,
          content: const TextContent('Le second.'),
        ),
      );
}

/// Gives the test a viewport large enough for the desktop layout.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Flushes the microtasks and the frames the screen needs.
Future<void> settle(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The strings of the screen, read from the tree the test just built.
AppLocalizations stringsOf(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(HistoryScreen)));
}

/// Wraps the screen in a provider scope holding the fake.
Widget harness(FakeRevisionRepository repository) {
  return ProviderScope(
    overrides: [revisionRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HistoryScreen(documentId: kHistoryDocumentId),
    ),
  );
}

/// The fake that serves the history of the manuscript.
FakeRevisionRepository fakeHistoryRepository() {
  return FakeRevisionRepository(
    documents: <String, CrdtDocument>{
      kHistoryDocumentId: fakeHistoryDocument(),
    },
  );
}

void main() {
  testWidgets('the screen lists the revisions of the document', (tester) async {
    useSurface(tester, const Size(1200, 1400));

    await tester.pumpWidget(harness(fakeHistoryRepository()));
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.historyRevisionLabel(1)), findsOneWidget);
    expect(find.text(strings.historyRevisionLabel(2)), findsOneWidget);
    expect(find.text(strings.historyRevisionLabel(3)), findsOneWidget);
  });

  testWidgets('the detail shows the difference of the newest revision', (
    tester,
  ) async {
    useSurface(tester, const Size(1200, 1400));

    await tester.pumpWidget(harness(fakeHistoryRepository()));
    await settle(tester);

    // La derniere revision a ajoute un bloc : l'ecran le dit, et montre
    // le texte du bloc.
    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.historyChangeAdded), findsOneWidget);
    expect(find.text('Le second.'), findsOneWidget);
  });

  testWidgets('picking a revision shows the blocks it changed', (tester) async {
    useSurface(tester, const Size(1200, 1400));

    await tester.pumpWidget(harness(fakeHistoryRepository()));
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(find.text(strings.historyRevisionLabel(2)));
    await settle(tester);

    // La deuxieme revision a corrige le premier paragraphe : l'ecran
    // montre le texte d'avant et le texte d'apres.
    expect(find.text(strings.historyChangeModified), findsOneWidget);
    expect(find.text(strings.historyChangeBefore), findsOneWidget);
    expect(find.text(strings.historyChangeAfter), findsOneWidget);
    expect(find.text('Le premier.'), findsOneWidget);
    expect(find.text('Le premier mot.'), findsOneWidget);
  });

  testWidgets('the screen shows the empty state without any revision', (
    tester,
  ) async {
    useSurface(tester, const Size(1200, 1400));

    await tester.pumpWidget(harness(FakeRevisionRepository()));
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.byType(LimpidEmptyState), findsOneWidget);
    expect(find.text(strings.historyEmptyTitle), findsOneWidget);
  });
}
