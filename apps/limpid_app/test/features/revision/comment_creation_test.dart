import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/revision_anchors.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_app/src/features/revision/revision_panel.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_selection_bar.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_toolbar.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import '../../editor/fakes.dart';
import 'fakes.dart';

/// L'identifiant de la scène ouverte.
const String _kSceneId = 'scene-1';

/// Le texte de la scène.
const String _kSceneText = 'Le sel qui vient des murs recouvre les vitres.';

/// Le message que l'auteur écrit.
const String _kComment = 'Ce passage ne va pas.';

/// Les mots que l'auteur sélectionne.
const String _kSelected = 'sel qui';

/// L'identifiant du bloc qui porte le texte.
const BlockId _kBlockId = BlockId('block-1');

/// Donne au test une surface assez large pour la disposition du bureau.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Vide les micro-tâches et les images dont l'écran a besoin.
Future<void> settle(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Bâtit le dépôt du manuscrit : une scène, un paragraphe.
FakeManuscriptRepository buildManuscriptRepository() {
  return FakeManuscriptRepository(
    chapters: <Chapter>[fakeChapter(id: 'chapitre-1', title: 'Le sel')],
    scenes: <String, List<Scene>>{
      'chapitre-1': <Scene>[
        fakeScene(
          id: _kSceneId,
          chapterId: 'chapitre-1',
          title: 'La plage à marée basse',
        ),
      ],
    },
    documents: <String, CrdtDocument>{
      '$_kSceneId-document': fakeDocument(
        documentId: '$_kSceneId-document',
        text: _kSceneText,
      ),
    },
  );
}

/// Bâtit le dépôt de la relecture : aucun fil pour l'instant.
FakeRevisionRepository buildRevisionRepository() {
  return FakeRevisionRepository(
    threads: const <CommentThread>[],
    members: <ProjectMember>[
      fakeMember(
        id: 'auteur-1',
        displayName: 'Ines Barreau',
        role: ProjectRole.owner,
      ),
    ],
  );
}

/// Enveloppe l'écran dans une portée qui tient les doublures.
Widget harness({
  required FakeManuscriptRepository manuscript,
  required FakeRevisionRepository revision,
}) {
  return ProviderScope(
    overrides: [
      manuscriptRepositoryProvider.overrideWithValue(manuscript),
      syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
      aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
      revisionRepositoryProvider.overrideWithValue(revision),
      authorIdProvider.overrideWithValue(kRevisionAuthor),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WritingScreen(projectId: kRevisionProjectId),
    ),
  );
}

void main() {
  late FakeManuscriptRepository manuscript;
  late FakeRevisionRepository revision;

  setUp(() {
    manuscript = buildManuscriptRepository();
    revision = buildRevisionRepository();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      harness(manuscript: manuscript, revision: revision),
    );
    await settle(tester);
  }

  AppLocalizations stringsOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(WritingScreen)));

  /// Ouvre le panneau de la relecture.
  Future<void> openReview(WidgetTester tester) async {
    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(WritingToolbar),
        matching: find.text(strings.writingReview),
      ),
    );
    await settle(tester);
  }

  /// Sélectionne le passage `start`..`end` du manuscrit.
  Future<void> selectPassageOf(WidgetTester tester, int start, int end) async {
    final LimpidSceneEditor editor = tester.widget<LimpidSceneEditor>(
      find.byType(LimpidSceneEditor),
    );
    selectPassage(editor.controller!, start, end);
    await settle(tester);
  }

  /// Écrit le commentaire et l'envoie.
  Future<void> writeTheComment(
    WidgetTester tester, {
    required String body,
  }) async {
    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(WritingSelectionBar),
        matching: find.text(strings.revisionComment),
      ),
    );
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(LimpidDialog),
        matching: find.byType(LimpidTextField),
      ),
      body,
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(LimpidDialog),
        matching: find.widgetWithText(LimpidButton, strings.revisionComment),
      ),
    );
    // La fenêtre se ferme : il faut laisser sa transition se terminer.
    await tester.pumpAndSettle();
  }

  testWidgets('the author comments a passage of the manuscript', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);
    await openReview(tester);

    // L'action n'apparaît que sur une sélection.
    expect(find.byType(WritingSelectionBar), findsNothing);

    await selectPassageOf(tester, 3, 10);

    expect(find.byType(WritingSelectionBar), findsOneWidget);
    expect(find.text(_kSelected), findsOneWidget);

    await writeTheComment(tester, body: _kComment);

    // La marque part comme une opération du CRDT.
    final List<AddMarkOp> marks = manuscript.operations
        .whereType<AddMarkOp>()
        .toList(growable: false);
    expect(marks, hasLength(1));
    expect(marks.single.blockId, _kBlockId);
    expect(marks.single.range, const MarkRange(start: 3, end: 10));
    expect(marks.single.type, MarkType.comment);
    expect(marks.single.body, _kComment);

    // Le fil porte l'identifiant, la marque, le message, l'auteur et la date.
    expect(revision.saved, hasLength(1));
    final CommentThread thread = revision.saved.single;
    expect(thread.markId, marks.single.markId);
    expect(thread.comments, hasLength(1));
    expect(thread.comments.single.body, _kComment);
    expect(thread.comments.single.author, kRevisionAuthor);
    expect(thread.comments.single.createdAt, isA<DateTime>());
    expect(thread.isResolved, isFalse);

    // L'extrait porte les mots commentés.
    expect(revision.excerpts[thread.id.value], _kSelected);

    // Le fil apparaît dans la liste des fils à traiter : la section des fils
    // résolus reste fermée.
    expect(
      find.descendant(
        of: find.byType(RevisionPanel),
        matching: find.text(_kComment),
      ),
      findsOneWidget,
    );
    expect(find.text(stringsOf(tester).revisionResolved), findsNothing);

    // La marque ancre le fil sur la plage sélectionnée.
    final LimpidSceneEditor editor = tester.widget<LimpidSceneEditor>(
      find.byType(LimpidSceneEditor),
    );
    expect(editor.commentAnchors, hasLength(1));
    expect(editor.commentAnchors.single.id, marks.single.markId.value);
    expect(
      editor.commentAnchors.single.range,
      const MarkRange(start: 3, end: 10),
    );
  });

  testWidgets('a comment without a word is refused', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    await selectPassageOf(tester, 3, 10);

    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(WritingSelectionBar),
        matching: find.text(strings.revisionComment),
      ),
    );
    await settle(tester);

    // Le bouton reste désactivé tant que le message est vide.
    final LimpidButton button = tester.widget<LimpidButton>(
      find.descendant(
        of: find.byType(LimpidDialog),
        matching: find.widgetWithText(LimpidButton, strings.revisionComment),
      ),
    );
    expect(button.onPressed, isNull);

    // Aucun fil, aucune marque.
    expect(revision.saved, isEmpty);
    expect(manuscript.operations.whereType<AddMarkOp>(), isEmpty);
  });

  testWidgets('a failed writing is told and no thread appears', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);
    manuscript.failOnApply = true;

    await selectPassageOf(tester, 3, 10);
    await writeTheComment(tester, body: _kComment);

    // L'échec est dit.
    expect(find.text(stringsOf(tester).revisionActionFailed), findsOneWidget);

    // Aucun fil n'apparaît.
    expect(revision.saved, isEmpty);
    expect(find.text(_kComment), findsNothing);
  });

  group("l'ancre suit le texte réécrit", () {
    test('la plage de la marque est recalculée sur le texte effectif', () {
      const DocumentId documentId = DocumentId('document-1');
      final CrdtDocument document = CrdtDocument.empty(documentId)
          .apply(
            const InsertBlockOp(
              doc: documentId,
              lamport: 1,
              author: kFakeAuthor,
              blockId: _kBlockId,
              parent: null,
              order: OrderKey.initial,
              type: BlockType.paragraph,
              content: TextContent('Le sel qui vient des murs'),
            ),
          )
          .apply(
            const AddMarkOp(
              doc: documentId,
              lamport: 2,
              author: kFakeAuthor,
              markId: MarkId('marque-1'),
              blockId: _kBlockId,
              type: MarkType.comment,
              range: MarkRange(start: 3, end: 10),
              body: _kComment,
            ),
          )
          .apply(
            const UpdateContentOp(
              doc: documentId,
              lamport: 3,
              author: kFakeAuthor,
              blockId: _kBlockId,
              content: TextContent('Le sel fin qui vient des murs'),
            ),
          );
      final List<RevisionAnchor> anchors = revisionAnchorsOf(
        document: document,
        threads: <CommentThread>[fakeThread(id: 'fil-1', markId: 'marque-1')],
      );

      // La marque suit les mots qu'elle couvre : ils ont été déplacés par
      // la réécriture.
      expect(anchors.single.range, const MarkRange(start: 3, end: 14));
      expect(anchors.single.excerpt, 'sel fin qui');
    });
  });
}
